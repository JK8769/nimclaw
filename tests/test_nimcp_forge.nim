import std/[asyncdispatch, json, tables, os, strutils]
import nimclaw/agent/loop
import nimclaw/config
import nimclaw/bus
import nimclaw/providers/http
import nimclaw/tools/[registry, spawn, subagent, forge, base]

proc getConfigPath*(): string =
  getHomeDir() / ".nimclaw" / "config.json"

proc main() {.async.} =
  echo "--- nimclaw MCP Forge Verification ---"
  let cfg = loadConfig(getConfigPath())
  let bus = newMessageBus()
  let al = newAgentLoop(cfg, bus, createProvider(cfg))
  
  let forgeName = "api_analyzer"
  let forgeCode = """
import mcp

let server = mcpServer("api_analyzer", "1.0.0"):
  mcpTool:
    proc analyze_api(url: string): string =
      ## Analyze a mock API URL
      return "Analysis for " & url & ": Healthy, 200 OK, latency 20ms"

when isMainModule:
  let transport = newStdioTransport()
  transport.serve(server)
"""

  echo "[1/3] Forging api_analyzer using NimCP..."
  await sleepAsync(100)
  
  let forgeRes = await al.tools.executeWithContext("forge_mcp_tool", {
    "name": %forgeName,
    "code": %forgeCode,
    "description": %"Analyzes API health and latency"
  }.toTable, "cli", "direct", "nimcp-verify")
  
  echo "      Result: ", forgeRes
  if forgeRes.contains("Failed"):
    echo "ERROR: Forge failed!"
    quit(1)

  echo "[2/3] Calling forged NimCP tool..."
  let toolName = "mcp_" & forgeName & "_analyze_api"
  let (tool, ok) = al.tools.get(toolName)
  if not ok:
    echo "ERROR: Tool " & toolName & " not found in registry!"
    echo "Registered tools: ", al.tools.getSummaries().join(", ")
    quit(1)
    
  let callRes = await al.tools.executeWithContext(toolName, {
    "url": %"https://api.example.com/v1"
  }.toTable, "cli", "direct", "nimcp-verify")
  
  echo "      Call Result: ", callRes
  if callRes.contains("Healthy"):
    echo "[3/3] Verification SUCCESS!"
  else:
    echo "ERROR: Unexpected tool output!"
    quit(1)

waitFor main()
