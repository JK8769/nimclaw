import std/[os, json, tables, asyncdispatch]
import ../src/nimclaw/agent/social_sensors
import ../src/nimclaw/agent/context
import ../src/nimclaw/tools/query_graph

proc testJSE() =
  let workspace = "/Users/owaf/.nimclaw/workspace"
  echo "--- Starting JSE Logic Test (Lexi) ---"
  
  # 1. Load the graph
  var graph = loadWorld(workspace)
  echo "Entities loaded: ", graph.entities.len
  
  # 2. Setup Tool
  let builder = newContextBuilder(workspace, @[])
  builder.graph = graph
  let tool = newQueryGraphTool(builder)
  
  # 3. Test filter for Agent
  echo "\nTesting: ['filter', 'Agent']"
  let res1 = waitFor tool.execute(%* {"expression": ["filter", "Agent"]})
  let jRes1 = parseJson(res1)
  echo "First Agent Name: ", jRes1[0]["name"].getStr()
  echo "First Agent Title: ", jRes1[0]["jobTitle"].getStr()
  
  # 4. Test relationships
  echo "\nTesting: ['relationships', 'nc:2', 'serves']"
  let res2 = waitFor tool.execute(%* {"expression": ["relationships", "nc:2", "serves"]})
  echo res2
  
  # 5. Test find Lexi
  echo "\nTesting: ['find', 'Lexi']"
  let res3 = waitFor tool.execute(%* {"expression": ["find", "Lexi"]})
  let jRes3 = parseJson(res3)
  echo "Found ID: ", jRes3["id"].getStr()
  echo "Found Name: ", jRes3["name"].getStr()

if isMainModule:
  testJSE()
