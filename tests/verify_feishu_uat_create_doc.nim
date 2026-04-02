import std/[asyncdispatch, json, os, strutils, tables]

import src/nimclaw/mcp/client

proc main() {.async.} =
  let secretsPath = ".nimclaw/workspace/offices/lexi/mcp/feishu_uat_v1/secrets/feishu_uat.json"
  if not fileExists(secretsPath):
    raise newException(ValueError, "missing secrets file: " & secretsPath)
  let secrets = parseFile(secretsPath)
  if secrets.kind != JObject or secrets.len == 0:
    raise newException(ValueError, "empty secrets")

  var appId = ""
  var userOpenId = ""
  for _, v in secrets.pairs:
    appId = v.getOrDefault("appId").getStr("")
    userOpenId = v.getOrDefault("userOpenId").getStr("")
    if appId.len > 0 and userOpenId.len > 0:
      break
  if appId.len == 0 or userOpenId.len == 0:
    raise newException(ValueError, "could not resolve appId/userOpenId from secrets")

  let binPath = ".nimclaw/workspace/offices/lexi/mcp/feishu_uat_v1/bin/feishu_uat_v1"
  let c = await connectMcpServer(binPath, @[])
  defer: c.stop()

  let tools = await c.listTools()
  var createTool: McpTool = nil
  for t in tools:
    if t.name() == "mcp_feishu_uat_v1_feishu_create_doc":
      createTool = t
      break
  if createTool.isNil:
    raise newException(ValueError, "feishu_create_doc tool not found")

  let markdown = "# UAT Create Doc Test\n\nThis is a test document created via feishu_uat_v1.\n"
  let title = "UAT Create Doc Test"

  let args = {
    "markdown": %markdown,
    "title": %title,
    "app_id": %appId,
    "user_open_id": %userOpenId
  }.toTable

  let output = await createTool.execute(args)
  echo output.strip()

waitFor main()
