import std/[asyncdispatch, json, tables, strutils]
import types

type
  ReplyTool* = ref object of ContextualTool
    sendCallback*: types.SendCallback

proc newReplyTool*(): ReplyTool =
  ReplyTool()

proc setSendCallback*(t: ReplyTool, callback: types.SendCallback) =
  t.sendCallback = callback

method name*(t: ReplyTool): string = "reply"
method description*(t: ReplyTool): string = "Send a direct message back to the current chat. Use this for status updates, quick answers, or proactive conversation during a task."
method parameters*(t: ReplyTool): Table[string, JsonNode] =
  {
    "type": %"object",
    "properties": %*{
      "content": {
        "type": "string",
        "description": "The message content to send"
      },
      "message": {
        "type": "string",
        "description": "Alias of content (backwards compatibility). Prefer using content."
      },
      "msg_type": {
        "type": "string",
        "description": "Feishu-only. Use 'interactive' to send a CardKit message."
      },
      "card": {
        "type": "object",
        "description": "Feishu-only. CardKit card JSON object. If provided with msg_type='interactive', sends an interactive card."
      },
      "feishu_card": {
        "type": "object",
        "description": "Feishu-only. CardKit card JSON object. Prefer using this for interactive cards."
      }
    },
    "required": %[]
  }.toTable

method execute*(t: ReplyTool, args: Table[string, JsonNode]): Future[string] {.async.} =
  if t.sessionKey.startsWith("system:"):
    return "Error: Communication tools are disabled for background tasks. Please keep your response internal."
  
  var content = ""
  if args.hasKey("feishu_card") or (args.getOrDefault("msg_type").getStr("") == "interactive" and args.hasKey("card")):
    if t.channel != "feishu":
      return "Error: feishu_card can only be used in Feishu channel"
    let card = if args.hasKey("feishu_card"): args["feishu_card"] else: args["card"]
    if card.kind != JObject:
      return "Error: card must be a JSON object"
    content = $(%*{
      "nimclaw_feishu": {
        "msg_type": "interactive",
        "card": card
      }
    })
  else:
    if args.hasKey("content"):
      content = args["content"].getStr()
    elif args.hasKey("message"):
      content = args["message"].getStr()
    else:
      return "Error: content is required"

  if t.channel == "" or t.chatID == "":
    return "Error: No active chat context found for reply"

  if t.sendCallback == nil:
    return "Error: Reply callback not configured"

  try:
    await t.sendCallback(t.channel, t.chatID, content, t.agentName, t.replyToMessageID, t.appID)
    return "Reply sent successfully to " & t.channel & ":" & t.chatID
  except Exception as e:
    return "Error sending reply: " & e.msg
