import std/[asyncdispatch, json, tables, os, strutils]
import nimclaw/agent/loop
import nimclaw/config
import nimclaw/bus
import nimclaw/providers/types as providers_types
import nimclaw/providers/http
import nimclaw/tools/[registry, spawn, subagent, forge, base]

# Mock type casting for tool access
type
  ActualSpawnTool = ref object of ContextualTool
    manager*: SubagentManager

proc getConfigPath*(): string =
  getHomeDir() / ".nimclaw" / "config.json"

proc main() {.async.} =
  # Heartbeat to keep dispatcher alive
  asyncCheck (proc() {.async.} =
    while true:
      await sleepAsync(500)
  )()

  echo "--- nimclaw JIT Forge & Sub-agent Demo ---"
  let cfg = loadConfig(getConfigPath())
  let bus = newMessageBus()
  
  # Use the real provider to allow sub-agent to actually "think"
  let al = newAgentLoop(cfg, bus, createProvider(cfg))
  
  let forgeCode = """
import std/[json, strutils, osproc, os]

proc reply(node: JsonNode) =
  echo $node
  stdout.flushFile()

proc main() =
  while not stdin.endOfFile():
    let line = try: stdin.readLine() except EOFError: ""
    if line == "": 
      sleep(10)
      continue
    let trimmed = line.strip()
    if not (trimmed.startsWith("{") and trimmed.endsWith("}")): continue
    try:
      let req = parseJson(trimmed)
      if req.hasKey("method"):
        let meth = req["method"].getStr()
        let id = if req.hasKey("id"): req["id"] else: %*JNull
        case meth:
        of "initialize":
          reply(%*{"jsonrpc": "2.0", "id": id, "result": {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}}, "serverInfo": {"name": "nim-lang-server", "version": "1.0.0"}}})
        of "tools/list":
          reply(%*{"jsonrpc": "2.0", "id": id, "result": {"tools": [{"name": "nim_check", "description": "Check Nim file", "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}]}})
        of "tools/call":
          let path = req["params"]["arguments"]["path"].getStr()
          let (output, code) = execCmdEx("nim check --hints:off " & quoteShell(path))
          reply(%*{"jsonrpc": "2.0", "id": id, "result": {"content": [{"type": "text", "text": "Exit code: " & $code & "\nOutput:\n" & output}]}})
        of "notifications/initialized": discard
    except Exception: discard
if isMainModule: main()
"""

  echo "[1/4] Forging nim_lang_server..."
  # Add a tiny sleep to ensure dispatcher is initialized
  await sleepAsync(100)
  
  let forgeRes = await al.tools.executeWithContext("forge_mcp_tool", {
    "name": %"nim_lang_server",
    "code": %forgeCode
  }.toTable, "cli", "direct", "jit-demo")
  echo "      Result: ", forgeRes

  if forgeRes.contains("Failed"):
    echo "ERROR: Forge failed!"
    return

  # Verify tool is in registry
  let (checkTool, registered) = al.tools.get("mcp_nim_lang_server_nim_check")
  writeFile("demo_error.nim", "proc greet() = echo \"Hello\"\ngreet(123) # Type mismatch")

  echo "[3/4] Spawning sub-agent..."
  let spawnMsg = await al.tools.executeWithContext("spawn", {
    "task": %"Use the mcp_nim_lang_server_nim_check tool to find the error in demo_error.nim. Fix it (it expects no arguments) and verify it is clean with the same tool. Return only the final fixed code.",
    "label": %"Language Fixer Subagent"
  }.toTable, "cli", "direct", "jit-demo")
  echo "      Result: ", spawnMsg

  # Polling for completion
  let parts = spawnMsg.split("with ID ")
  if parts.len < 2:
    echo "ERROR: Failed to parse task ID from: ", spawnMsg
    return
  let taskID = parts[1].split(" ")[0].strip()
  echo "[4/4] Polling sub-agent task: ", taskID
  
  let (toolObj, ok) = al.tools.get("spawn")
  if not ok:
    echo "ERROR: Spawn tool not found!"
    return
  let spawnTool = toolObj.SpawnTool
  let sm = spawnTool.manager
  
  while true:
    let status = sm.tasks[taskID].status
    if status == "completed":
      echo "\n--- DEMO SUCCESS ---"
      echo "Subagent Output:\n", sm.tasks[taskID].result
      break
    elif status == "failed":
      echo "\n--- DEMO FAILED ---"
      echo "Error: ", sm.tasks[taskID].result
      break
    stdout.write "."; stdout.flushFile()
    await sleepAsync(2000)

waitFor main()
