import std/[json, options]

include ../src/nimclaw/channels/feishu

when isMainModule:
  let card = %*{
    "schema": "2.0",
    "config": %*{"wide_screen_mode": false},
    "header": %*{"title": %*{"tag": "plain_text", "content": "t"}, "template": "blue"},
    "body": %*{"elements": %*[%*{"tag": "markdown", "content": "hi"}]}
  }
  let envelope = $(%*{"nimclaw_feishu": %*{"msg_type": "interactive", "card": card}})
  let extracted = tryExtractInteractiveCard(envelope)
  doAssert isSome(extracted)
  let parsed = parseJson(get(extracted))
  doAssert parsed{"schema"}.getStr() == "2.0"
  echo "ok"
