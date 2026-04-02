import std/[asyncdispatch, httpclient, json, os, strutils, times]

proc nimclawDir(): string =
  let v = getEnv("NIMCLAW_DIR", "")
  if v.len > 0: return v
  getHomeDir() / ".nimclaw"

proc loadEnabledApp(): tuple[appId: string, appSecret: string] =
  let root = parseJson(readFile(nimclawDir() / "BASE.json"))
  let apps = root{"config"}{"channels"}{"feishu"}{"apps"}
  if apps.kind != JArray:
    return ("", "")
  for a in apps:
    if a{"enabled"}.kind == JBool and a{"enabled"}.getBool() == false:
      continue
    let id = a{"app_id"}.getStr("")
    let sec = a{"app_secret"}.getStr("")
    if id.len > 0 and sec.len > 0:
      return (id, sec)
  ("", "")

proc getTenantToken(appId, appSecret: string): Future[string] {.async.} =
  let client = newAsyncHttpClient()
  client.headers["Content-Type"] = "application/json"
  try:
    let url = "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal"
    let payload = %*{"app_id": appId, "app_secret": appSecret}
    let resp = await client.post(url, $payload)
    let body = await resp.body
    let j = parseJson(body)
    if j.hasKey("tenant_access_token"):
      return j["tenant_access_token"].getStr()
    return ""
  finally:
    client.close()

proc cardkitCreate(token: string, card: JsonNode): Future[tuple[cardId: string, status: string, code: int, msg: string]] {.async.} =
  let client = newAsyncHttpClient()
  client.headers["Authorization"] = "Bearer " & token
  client.headers["Content-Type"] = "application/json"
  try:
    let url = "https://open.feishu.cn/open-apis/cardkit/v1/cards"
    let payload = %*{"type": "card_json", "data": $card}
    let resp = await client.post(url, $payload)
    let body = await resp.body
    let j = parseJson(body)
    let c = j.getOrDefault("code").getInt(-1)
    let m = j.getOrDefault("msg").getStr("")
    if resp.status.startsWith("200") and c == 0:
      return (j{"data"}{"card_id"}.getStr(""), resp.status, c, m)
    return ("", resp.status, c, m)
  finally:
    client.close()

proc sendInteractive(token, chatId, cardId: string): Future[tuple[ok: bool, status: string, code: int, msg: string, messageId: string]] {.async.} =
  let client = newAsyncHttpClient()
  client.headers["Authorization"] = "Bearer " & token
  client.headers["Content-Type"] = "application/json"
  try:
    let url = "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=chat_id"
    let content = $(%*{"type": "card", "data": %*{"card_id": cardId}})
    let payload = %*{"receive_id": chatId, "msg_type": "interactive", "content": content}
    let resp = await client.post(url, $payload)
    let body = await resp.body
    let j = parseJson(body)
    let c = j.getOrDefault("code").getInt(-1)
    let m = j.getOrDefault("msg").getStr("")
    let mid = j{"data"}{"message_id"}.getStr("")
    (resp.status.startsWith("200") and c == 0, resp.status, c, m, mid)
  finally:
    client.close()

when isMainModule:
  let (appId, appSecret) = loadEnabledApp()
  if appId.len == 0:
    quit("no enabled feishu app in BASE.json")
  let chatId = getEnv("FEISHU_TEST_CHAT_ID", "oc_136b46cfde0e7ddeddc43f24bd28e702")
  let token = waitFor getTenantToken(appId, appSecret)
  if token.len == 0:
    quit("failed to get tenant token")

  let card = %*{
    "schema": "2.0",
    "config": %*{"wide_screen_mode": false},
    "header": %*{"title": %*{"tag": "plain_text", "content": "CardKit Test"}, "template": "blue"},
    "body": %*{"elements": %*[%*{"tag": "markdown", "content": "hello"}]}
  }
  let (cardId, status, code, msg) = waitFor cardkitCreate(token, card)
  var sendStatus = ""
  var sendCode = -1
  var sendMsg = ""
  var messageId = ""
  var ok = false
  if cardId.len > 0:
    let r = waitFor sendInteractive(token, chatId, cardId)
    ok = r.ok
    sendStatus = r.status
    sendCode = r.code
    sendMsg = r.msg
    messageId = r.messageId
  let report = %*{
    "ok": ok,
    "app_id": appId,
    "chat_id": chatId,
    "card_id_len": cardId.len,
    "cardkit_http_status": status,
    "cardkit_code": code,
    "cardkit_msg": msg,
    "send_http_status": sendStatus,
    "send_code": sendCode,
    "send_msg": sendMsg,
    "message_id": messageId,
    "time": $now()
  }
  let outPath = nimclawDir() / "cardkit_send_check.json"
  writeFile(outPath, $report)
  echo $report
