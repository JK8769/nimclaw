import src/nimclaw/mcp

let server = mcpServer("hello_world", "1.0.0"):
  mcpTool:
    proc greet(name: string): string =
      ## Greet someone by name
      ## - name: The name of the person to greet
      return "Hello, " & name & "!"

when isMainModule:
  let transport = newStdioTransport()
  transport.serve(server)