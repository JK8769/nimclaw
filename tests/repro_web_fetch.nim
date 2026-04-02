import std/[asyncdispatch, json, tables]
import nimclaw/tools/web
import curly
import nimclaw/lib/malebolgia
import nimclaw/tools/types

proc test() {.async.} =
  let curly = newCurly()
  let master1 = createMaster()
  let master2 = createMaster()
  
  let fetchTool = newWebFetchTool(50000, curly, master1)
  let searchTool = newWebSearchTool("", 5, curly, master2)
  
  let queries = ["robot claw news", "nim programming language", "TechCrunch claw"]
  for q in queries:
    echo "--- Testing Web Search for: ", q, " ---"
    try:
      let args = {"query": %q}.toTable
      let result = await searchTool.execute(args)
      echo "Result: ", result
    except Exception as e:
      echo "Search Error: ", e.msg
    echo "----------------------------------------\n"

  let urls = [
    "https://arstechnica.com/search/?query=claw+machine",
    "https://www.theverge.com/search?q=robot+gripper",
    "https://techcrunch.com/search/claw"
  ]
  
  for url in urls:
    echo "--- Testing Web Fetch for: ", url, " ---"
    try:
      let args = {"url": %url}.toTable
      let result = await fetchTool.execute(args)
      let js = parseJson(result)
      echo "Status: ", js["status"].getInt()
      echo "Length: ", js["length"].getInt()
      echo "Extractor: ", js["extractor"].getStr()
      if js["length"].getInt() < 200:
        echo "Content too short! Body: "
        echo js["text"].getStr()
      else:
        echo "Content snippet: ", js["text"].getStr()[0..200], "..."
    except Exception as e:
      echo "Fetch Error: ", e.msg
    echo "----------------------------------------\n"

waitFor test()
