import std/[asyncdispatch, json, tables, options, os, strutils]
import nimclaw/tools/forward
import nimclaw/tools/types
import nimclaw/agent/cortex

proc main() {.async.} =
  let tmp = getTempDir() / "nimclaw_forward_envelope_test"
  if not dirExists(tmp):
    createDir(tmp)

  let guestID = "ou_test_guest_envelope"
  let relations = %*[
    {
      "name": "Alice",
      "kind": "Person",
      "identity": "Guest",
      "trustLevel": 10,
      "etiquette": "",
      "identifiers": {
        "feishu": [guestID]
      }
    }
  ]
  writeFile(tmp / "RELATIONS.json", $relations)

  var g = WorldGraph(
    workspace: tmp,
    filePath: tmp / "world.json",
    nextID: 10,
    entities: initTable[WorldEntityID, WorldEntity](),
    providers: newJObject(),
    config: newJObject(),
    nameIndex: initTable[string, WorldEntityID](),
    nknIndex: initTable[string, WorldEntityID](),
    idAliasIndex: initTable[string, WorldEntityID]()
  )

  let viaID = WorldEntityID(2)
  let leadID = WorldEntityID(3)

  g.entities[viaID] = WorldEntity(
    id: viaID,
    kind: ekAI,
    name: "Lexi",
    identifiers: initTable[string, string](),
    memberOf: @[],
    department: @[],
    parentOrganization: none(WorldEntityID),
    reportsTo: @[RelationshipLink(targetID: leadID, annotation: none(RelationshipAnnotation))],
    serves: @[],
    custom: newJObject()
  )

  var leadIdents = initTable[string, string]()
  leadIdents["feishu"] = "oc_lead_chat"
  g.entities[leadID] = WorldEntity(
    id: leadID,
    kind: ekPerson,
    name: "Jerry",
    identifiers: leadIdents,
    memberOf: @[],
    department: @[],
    parentOrganization: none(WorldEntityID),
    reportsTo: @[],
    serves: @[],
    custom: newJObject()
  )

  g.nameIndex["Lexi"] = viaID
  g.nameIndex["Jerry"] = leadID

  var lastChannel = ""
  var lastChat = ""
  var lastContent = ""

  let t = newForwardTool(tmp)
  t.setSendCallback(proc(channel, chatID, content, senderAgent: string): Future[void] {.async.} =
    lastChannel = channel
    lastChat = chatID
    lastContent = content
  )
  t.setContext("feishu", "oc_guest_chat", "feishu:oc_guest_chat:" & guestID, guestID, "Lexi", "guest", "Lexi", "nc:2", guestID, g)

  var args = initTable[string, JsonNode]()
  args["from"] = %guestID
  args["to"] = %"Jerry"
  args["via"] = %"Lexi"
  args["content"] = %"I need help"
  args["note"] = %"Intent: help request. Risk: low. Recommend: ask for details."

  let res = await t.execute(args)
  doAssert res.startsWith("Forwarded successfully"), res
  doAssert lastChannel == "feishu"
  doAssert lastChat == "oc_lead_chat"
  doAssert "Forwarded by Lexi to Jerry" in lastContent
  doAssert "From: Alice on feishu" in lastContent
  doAssert "Guest ID: " & guestID in lastContent
  doAssert "Trust: 10/100 (Low)" in lastContent
  doAssert "Lexi summary:" in lastContent
  doAssert "Message:" in lastContent
  doAssert "nc:" notin lastContent

  lastChannel = ""
  lastChat = ""
  lastContent = ""

  var args2 = initTable[string, JsonNode]()
  args2["from"] = %"user"
  args2["via"] = %"user"
  args2["to"] = %"him"
  args2["content"] = %"hello back"
  t.setContext("feishu", "oc_jerry_chat", "feishu:oc_jerry_chat:ou_jerry", "ou_jerry", "Lexi", "Boss", "Lexi", "nc:2", "nc:3", g)
  let res2 = await t.execute(args2)
  doAssert res2.startsWith("Forwarded successfully")
  doAssert lastChannel == "feishu"
  doAssert lastChat == guestID
  doAssert lastContent == "Jerry asked me (Lexi) to reply: hello back"

  echo "OK"

waitFor main()
