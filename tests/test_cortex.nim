import os, options, tables, json
import src/nimclaw/agent/cortex

proc main() =
  let graph = loadWorld("/Users/owaf/Work/Agents/nimclaw/.nimclaw")
  echo "Graph loaded. Entities: ", graph.entities.len
  
  if graph.entities.hasKey(WorldEntityID(2)):
    let lexi = graph.entities[WorldEntityID(2)]
    echo "Lexi found: ", lexi.name
    echo "Lexi reportsTo: ", lexi.reportsTo.len
    for r in lexi.reportsTo:
      echo "  - target: ", r.targetID.uint32
      if r.annotation.isSome:
        echo "    annotation: ", r.annotation.get().role
  
  let (resID1, annot1) = graph.resolveUserGraph("feishu", "ou_b785f570411fcf8398abf8a5c75d0670", WorldEntityID(2))
  echo "resolveUserGraph(loop.nim test): ", resID1.uint32, " / annot: ", annot1.isSome
  
  let (resID2, annot2) = graph.resolveUserGraph("feishu", "nc:3", WorldEntityID(2))
  echo "resolveUserGraph(context.nim test): ", resID2.uint32, " / annot: ", annot2.isSome

main()
