import std/[asyncdispatch, json, os, strutils, tables]

import src/nimclaw/mcp/client

proc loadDotEnvValue(path, key: string): string =
  try:
    for raw in readFile(path).splitLines():
      let line = raw.strip()
      if line.len == 0 or line.startsWith("#"): continue
      if not line.contains("="): continue
      let parts = line.split("=", 1)
      if parts.len != 2: continue
      if parts[0].strip() == key:
        return parts[1].strip()
  except:
    discard
  ""

proc main() {.async.} =
  if getEnv("LARK_APP_ID", "").len == 0:
    let v = loadDotEnvValue(".nimclaw/workspace/offices/lexi/.env", "LARK_APP_ID")
    if v.len > 0: putEnv("LARK_APP_ID", v)
  if getEnv("LARK_APP_SECRET", "").len == 0:
    let v = loadDotEnvValue(".nimclaw/workspace/offices/lexi/.env", "LARK_APP_SECRET")
    if v.len > 0: putEnv("LARK_APP_SECRET", v)

  let chatId = getEnv("FEISHU_TEST_CHAT_ID", "oc_136b46cfde0e7ddeddc43f24bd28e702")

  let binPath = ".nimclaw/workspace/offices/lexi/mcp/feishu_v5/bin/feishu_v5"
  let c = await connectMcpServer(binPath, @[])
  defer: c.stop()
  let tools = await c.listTools()
  var imSend: McpTool = nil
  for t in tools:
    if t.name() == "mcp_feishu_v5_im_send":
      imSend = t
      break
  if imSend.isNil:
    raise newException(ValueError, "im_send tool not found")

  let card = %*{
    "config": %*{"wide_screen_mode": true},
    "header": %*{
      "title": %*{"tag": "plain_text", "content": "CardKit ping"},
      "template": "blue"
    },
    "elements": %*[
      %*{
        "tag": "div",
        "text": %*{"tag": "plain_text", "content": "If you see this, interactive works."}
      }
    ]
  }

  let envelope = %*{"msg_type": "interactive", "card": card}
  let args = {
    "receive_id": %chatId,
    "receive_id_type": %"chat_id",
    "content": %($envelope)
  }.toTable

  let output = await imSend.execute(args)
  echo output.strip()

waitFor main()
