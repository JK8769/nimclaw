import std/[asyncdispatch, json, tables, os]
import bus, bus_types, config, session, logger, providers/types
import agent/loop
import tools/registry

proc testPurge() {.async.} =
  var cfg = Config()
  cfg.agents.defaults.workspace = getTempDir() / "nimclaw_test_purge"
  if not dirExists(cfg.agents.defaults.workspace):
    createDir(cfg.agents.defaults.workspace)
    
  let bus = newMessageBus()
  # Mock provider
  let al = newAgentLoop(cfg, bus, nil, nil)
  
  echo "--- 1. Forging a tool ---"
  let forgeCode = """
import mcp
let server = mcpServer("test_tool", "1.0.0"):
  mcpTool:
    proc ping(): string = "pong"
when isMainModule:
  let transport = newStdioTransport()
  transport.serve(server)
"""
  let forgeResult = await al.tools.executeWithContext("forge_mcp_tool", {"name": %"test_tool", "code": %forgeCode}.toTable, "test", "test", "session-1")
  echo forgeResult
  
  echo "\n--- 2. Verifying tool exists ---"
  let (tool, found) = al.tools.get("mcp_test_tool_ping")
  echo "Found ping tool: ", found
  
  echo "\n--- 3. Purging the tool ---"
  let purgeResult = await al.tools.executeWithContext("purge_mcp_tool", {"name": %"test_tool"}.toTable, "test", "test", "session-1")
  echo purgeResult
  
  echo "\n--- 4. Verifying tool is gone ---"
  let (_, foundAfter) = al.tools.get("mcp_test_tool_ping")
  echo "Found ping tool after purge: ", foundAfter
  
  if found and not foundAfter:
    echo "\nVerification SUCCESS: Tool was registered and then successfully purged."
  else:
    echo "\nVerification FAILURE"
    quit(1)

waitFor testPurge()
