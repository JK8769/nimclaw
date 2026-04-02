import std/[json, os, options, tables, strutils]
import nimclaw/agent/[cortex, context, memory]
import nimclaw/skills/[installer, loader]

proc testDynamicPersona() =
  let workspace = getHomeDir() / ".nimclaw"
  let graph = loadWorld(workspace)
  
  # Find MultiPersonaTest ID
  let agentID = graph.nameIndex["MultiPersonaTest"]
  let ent = graph.entities[agentID]
  
  echo "DEBUG Agent Entity Name: ", ent.name
  if ent.custom != nil and ent.custom.hasKey("personas"):
    echo "DEBUG Personas found: ", ent.custom["personas"].pretty()
  else:
    echo "DEBUG Personas missing!"
    
  echo "\nTestAgent identity: ", graph.entities[graph.nameIndex["TestAgent"]].custom{"identity"}.getStr("MISSING")

when isMainModule:
  testDynamicPersona()
