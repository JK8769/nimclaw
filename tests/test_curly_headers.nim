import std/[asyncdispatch, json, tables]
import curly
import ../src/nimclaw/lib/malebolgia
import webby/httpheaders

proc test() {.async.} =
  let c = newCurly()
  var master = createMaster()
  
  var headers: seq[(string, string)] = @[]
  headers.add(("User-Agent", "Mozilla/5.0 (compatible; nimclaw/1.0)"))
  headers.add(("X-Test", "NimClaw-Test"))
  
  echo "--- Testing Curly (spawned) with api.duckduckgo.com ---"
  try:
    let url = "https://api.duckduckgo.com/?q=test&format=json"
    let fv = master.spawn c.get(url, headers = headers)
    let hasResult = await withTimeout(fv, 5000)
    if hasResult:
      let resp = fv.read()
      echo "Status: ", resp.code
      echo "Body Snippet: ", if resp.body.len > 100: resp.body[0..100] else: resp.body
    else:
      echo "Error: Request to DuckDuckGo timed out after 5 seconds"
  except Exception as e:
    echo "Error: ", e.msg

waitFor test()
