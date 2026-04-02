import std/[json, strutils]

proc main() =
  while not stdin.endOfFile():
    let line = try: stdin.readLine() except EOFError: ""
    if line == "": continue
    
    let trimmed = line.strip()
    if not (trimmed.startsWith("{") and trimmed.endsWith("}")):
      continue

    try:
      let req = parseJson(trimmed)
      if req.hasKey("method"):
        let meth = req["method"].getStr()
        let id = if req.hasKey("id"): req["id"] else: %*JNull
        
        case meth:
        of "initialize":
          echo $(%*{
            "jsonrpc": "2.0",
            "id": id,
            "result": {
              "protocolVersion": "2024-11-05",
              "capabilities": {
                "tools": {}
              },
              "serverInfo": {
                "name": "diagnostic-server",
                "version": "1.0.0"
              }
            }
          })
        of "notifications/initialized":
          discard
        of "tools/list":
          echo $(%*{
            "jsonrpc": "2.0",
            "id": id,
            "result": {
              "tools": [
                {
                  "name": "echo",
                  "description": "Echoes back the input text",
                  "inputSchema": {
                    "type": "object",
                    "properties": {
                      "text": { "type": "string" }
                    },
                    "required": ["text"]
                  }
                }
              ]
            }
          })
        of "tools/call":
          let name = req["params"]["name"].getStr()
          if name == "echo":
             let text = req["params"]["arguments"]["text"].getStr()
             echo $(%*{
               "jsonrpc": "2.0",
               "id": id,
               "result": {
                 "content": [
                   { "type": "text", "text": "Echo: " & text }
                 ]
               }
             })
        else:
          discard
    except Exception as e:
      stderr.writeLine("Error: " & e.msg)

if isMainModule:
  main()
