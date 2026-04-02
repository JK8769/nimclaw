import std/[asyncdispatch, json, tables, options, strutils]

import nimclaw/tools/reply
import nimclaw/tools/types

proc main() {.async.} =
  var captured = ""

  let t = newReplyTool()
  t.setContext(
    channel = "feishu",
    chatID = "oc_test_chat",
    sessionKey = "feishu:oc_test_chat:ou_test",
    senderID = "ou_test",
    recipientID = "cli_test",
    role = "user",
    agentName = "Lexi",
    agentID = "nc:2",
    logicalUserID = "ou_test",
    appID = "cli_test",
    replyToMessageID = "om_test",
    graph = nil
  )

  t.setSendCallback(proc(channel, chatID, content, senderAgent, replyToMessageID, appID: string): Future[void] {.async.} =
    captured = content
  )

  let card = %*{
    "config": %*{"wide_screen_mode": true},
    "header": %*{
      "title": %*{"tag": "plain_text", "content": "Test Card"},
      "template": "blue"
    },
    "elements": %*[
      %*{"tag": "div", "text": %*{"tag": "plain_text", "content": "hello"}}
    ]
  }

  var args = initTable[string, JsonNode]()
  args["msg_type"] = %"interactive"
  args["card"] = card

  let res = await t.execute(args)
  if not res.startsWith("Reply sent successfully"):
    raise newException(ValueError, "unexpected reply result: " & res)

  let j = parseJson(captured)
  if j.kind != JObject or not j.hasKey("nimclaw_feishu"):
    raise newException(ValueError, "missing nimclaw_feishu envelope")
  if j["nimclaw_feishu"].getOrDefault("msg_type").getStr() != "interactive":
    raise newException(ValueError, "msg_type not interactive")
  if j["nimclaw_feishu"].getOrDefault("card").kind != JObject:
    raise newException(ValueError, "card not object")

  echo "ok"

waitFor main()
