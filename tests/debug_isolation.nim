import nimcp, std/isolation

let server = mcpServer("test", "1.0.0"):
  mcpTool:
    proc hello(): string = "world"

when isMainModule:
  let transport = newStdioTransport()
  transport.serve(server)
