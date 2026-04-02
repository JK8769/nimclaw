import options, json, tables, strutils
import src/nimclaw/agent/cortex
import src/nimclaw/config

proc main() =
  let graph = loadWorld(getNimClawDir())
  echo "Graph loaded. Entities: ", graph.entities.len
  
  var agentId = WorldEntityID(0)
  let activeRecipient = "Lexi"
  if activeRecipient != "" and graph.nameIndex.hasKey(activeRecipient):
    agentId = graph.nameIndex[activeRecipient]
  echo "agentId: ", agentId.uint32
  
  let channel = "feishu"
  let senderID = "ou_b785f570411fcf8398abf8a5c75d0670"
  
  let (resolvedID, annotOpt) = graph.resolveUserGraph(channel, senderID, agentId)
  echo "resolvedID: ", resolvedID.uint32
  if annotOpt.isSome:
    echo "role: ", annotOpt.get().role
  else:
    echo "annotOpt is none!"

main()
