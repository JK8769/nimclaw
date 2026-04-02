import std/[asyncdispatch, httpclient, json, os, times]

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
    j.getOrDefault("tenant_access_token").getStr("")
  finally:
    client.close()

proc sendInteractiveDirect(token, chatId: string, card: JsonNode): Future[JsonNode] {.async.} =
  let client = newAsyncHttpClient()
  client.headers["Authorization"] = "Bearer " & token
  client.headers["Content-Type"] = "application/json"
  try:
    let url = "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=chat_id"
    let payload = %*{
      "receive_id": chatId,
      "msg_type": "interactive",
      "content": $card
    }
    let resp = await client.post(url, $payload)
    let body = await resp.body
    %*{
      "http_status": resp.status,
      "response": parseJson(body)
    }
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
    "config": %*{"wide_screen_mode": true},
    "header": %*{"title": %*{"tag": "plain_text", "content": "Legacy Card Test"}, "template": "blue"},
    "elements": %*[
      %*{"tag": "markdown", "content": "hello from legacy card json"}
    ]
  }

  let res = waitFor sendInteractiveDirect(token, chatId, card)
  let report = %*{"time": $now(), "chat_id": chatId, "result": res}
  let outPath = nimclawDir() / "interactive_direct_check.json"
  writeFile(outPath, $report)
  echo $report
