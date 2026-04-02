import std/[tables, json, strutils]

import src/nimclaw/agent/xml_tools

proc main() =
  let resp = """<|tool_calls_section_begin|>
<|tool_call_begin|> functions.mcp_feishu_v5_docx_create:9 <|tool_call_argument_begin|> {"title":"T","markdown":"# H\n\nHi"} <|tool_call_end|>
<|tool_calls_section_end|>"""

  let calls = parseXmlToolCalls(resp)
  doAssert calls.len == 1
  doAssert calls[0].name == "mcp_feishu_v5_docx_create"
  doAssert calls[0].arguments.hasKey("title")
  doAssert calls[0].arguments["title"].getStr() == "T"
  doAssert calls[0].arguments.hasKey("markdown")
  doAssert calls[0].arguments["markdown"].getStr().contains("Hi")
  echo "ok"

when isMainModule:
  main()
