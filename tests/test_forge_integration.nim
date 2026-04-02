import std/[asyncdispatch, tables, json, os, strutils]
import ../src/nimclaw/[agent/loop, config, bus]
import ../src/nimclaw/providers/types as providers_types
import ../src/nimclaw/tools/registry

# Mock provider for testing
type MockProvider = ref object of providers_types.LLMProvider
method chat*(p: MockProvider, messages: seq[providers_types.Message], tools: seq[providers_types.ToolDefinition], model: string, options: Table[string, JsonNode]): Future[providers_types.LLMResponse] {.async.} =
  # The first time it's called, it will call the forge tool
  # The second time, it will call the echo tool
  # The third time, it returns text.
  # For simplicity, we'll just return a tool call if the user message matches.
  if messages.len > 0 and messages[^1].content.contains("forge"):
    return providers_types.LLMResponse(
      content: "",
      tool_calls: @[providers_types.ToolCall(
        id: "call_1",
        name: "forge_mcp_tool",
        arguments: {
          "name": %*"auto-echo",
          "code": %*"""
import std/[json, strutils]
proc main() =
  while not stdin.endOfFile():
    let line = try: stdin.readLine() except EOFError: ""
    if line == "": continue
    let trimmed = line.strip()
    if not (trimmed.startsWith("{") and trimmed.endsWith("}")): continue
    try:
      let req = parseJson(trimmed)
      if req.hasKey("method"):
        let meth = req["method"].getStr()
        let id = if req.hasKey("id"): req["id"] else: %*JNull
        case meth:
        of "initialize":
          echo $(%*{"jsonrpc": "2.0", "id": id, "result": {"protocolVersion": "2024-11-05", "capabilities": {"tools": {}}, "serverInfo": {"name": "auto-echo", "version": "1.0.0"}}})
        of "tools/list":
          echo $(%*{"jsonrpc": "2.0", "id": id, "result": {"tools": [{"name": "echo", "description": "Echo", "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}}]}})
        of "tools/call":
          let text = req["params"]["arguments"]["text"].getStr()
          echo $(%*{"jsonrpc": "2.0", "id": id, "result": {"content": [{"type": "text", "text": "Forged Echo: " & text}]}})
    except Exception: discard
if isMainModule: main()
"""
        }.toTable
      )]
    )
  elif messages.len > 0 and "mcp_auto-echo_echo" in messages[^1].content:
    return providers_types.LLMResponse(content: "I've used the forged tool successfully.")
  else:
    return providers_types.LLMResponse(content: "Hello!")

proc test() {.async.} =
  let cfg = Config() # Default config
  let bus = newMessageBus()
  let provider = MockProvider()
  let al = newAgentLoop(cfg, bus, provider)
  
  let sessionKey = "forge-test-session"
  echo "--- Step 1: Agent decides to forge a tool ---"
  let res1 = await al.processDirect("Please forge an echo tool for me", sessionKey)
  echo "Agent Response: ", res1
  
  echo "Checking tool registry..."
  if "mcp_auto-echo_echo" in al.tools.list():
    echo "SUCCESS: Tool 'mcp_auto-echo_echo' is registered!"
  else:
    echo "ERROR: Tool was not registered."
    return

  echo "--- Step 2: Session finished (Implicitly purged by processDirect) ---"
  # processDirect calls runAgentLoop which calls purgeSession
  
  echo "Checking tool registry after loop..."
  if not ("mcp_auto-echo_echo" in al.tools.list()):
    echo "SUCCESS: Tool was purged correctly!"
  else:
    echo "ERROR: Tool was NOT purged."

if isMainModule:
  waitFor test()
