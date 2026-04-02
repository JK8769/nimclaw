import std/[asyncdispatch, tables, json]
import ../src/nimclaw/tools/[registry, types]
import ../src/nimclaw/mcp

proc test() {.async.} =
  let reg = newToolRegistry()
  echo "Registering diagnostic MCP server..."
  # Use the pre-compiled binary
  await reg.registerMcpServer("/Users/owaf/Work/Agents/nimclaw/tests/diagnostic_mcp")
  
  echo "Listing tools..."
  let tools = reg.list()
  echo "Available tools: ", tools
  
  if "mcp_diagnostic-server_echo" in tools:
    echo "Executing echo tool..."
    let args = {"text": %*"Hello World"}.toTable
    let res = await reg.executeWithContext("mcp_diagnostic-server_echo", args, "test", "user1", "session1")
    echo "Tool result: ", res
    
    echo "Unregistering MCP server..."
    reg.unregisterMcpServer("diagnostic-server")
    
    let toolsAfter = reg.list()
    echo "Available tools after: ", toolsAfter
    if not ("mcp_diagnostic-server_echo" in toolsAfter):
      echo "Unregistration successful!"
    else:
      echo "Error: Tool still present after unregistration!"

    echo "Testing session-scoped purging..."
    await reg.registerMcpServer("/Users/owaf/Work/Agents/nimclaw/tests/diagnostic_mcp", sessionKey = "session-purge-test")
    if "mcp_diagnostic-server_echo" in reg.list():
      echo "Session registration successful, now purging..."
      reg.purgeSession("session-purge-test")
      if not ("mcp_diagnostic-server_echo" in reg.list()):
        echo "Purge successful!"
      else:
        echo "Error: Tool still present after purge!"
  else:
    echo "Error: echo tool not found!"

if isMainModule:
  waitFor test()
