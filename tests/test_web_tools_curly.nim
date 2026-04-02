import std/[asyncdispatch, json, tables]
import nimclaw/tools/web
import curly
import nimclaw/lib/malebolgia
import nimclaw/tools/types

proc test() {.async.} =
  let curly = newCurly()
  let master1 = createMaster()
  let master2 = createMaster()
  
  # For DuckDuckGo (apiKey = "")
  let searchTool = newWebSearchTool("", 5, curly, master1)
  let fetchTool = newWebFetchTool(50000, curly, master2)
  
  echo "--- Testing Web Search (DuckDuckGo) ---"
  try:
    let args = {"query": %"nim programming language"}.toTable
    let searchResult = await searchTool.execute(args)
    echo "Search Result snippet:"
    if searchResult.len > 500:
      echo searchResult[0..500] & "..."
    else:
      echo searchResult
  except Exception as e:
    echo "Search Error: ", e.msg

  echo "\n--- Testing Web Fetch ---"
  try:
    let args = {"url": %"https://nim-lang.org"}.toTable
    let fetchResult = await fetchTool.execute(args)
    echo "Fetch Result (JSON):"
    echo fetchResult
  except Exception as e:
    echo "Fetch Error: ", e.msg

waitFor test()
