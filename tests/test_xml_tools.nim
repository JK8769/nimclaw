import std/[unittest, json, tables, strutils]
import ../src/nimclaw/agent/xml_tools

suite "XML Tool Call Parser":
  test "parse single tool call":
    let response = """Let me check that.
<tool_call>
{"name": "shell", "arguments": {"command": "ls -la"}}
</tool_call>"""
    let calls = parseXmlToolCalls(response)
    check calls.len == 1
    check calls[0].name == "shell"
    check calls[0].arguments["command"].getStr() == "ls -la"

  test "parse multiple tool calls":
    let response = """<tool_call>
{"name": "file_read", "arguments": {"path": "a.txt"}}
</tool_call>
<tool_call>
{"name": "file_read", "arguments": {"path": "b.txt"}}
</tool_call>"""
    let calls = parseXmlToolCalls(response)
    check calls.len == 2
    check calls[0].name == "file_read"
    check calls[1].name == "file_read"
    check calls[0].arguments["path"].getStr() == "a.txt"
    check calls[1].arguments["path"].getStr() == "b.txt"

  test "no tool calls returns empty":
    let response = "Just a normal response with no tools."
    let calls = parseXmlToolCalls(response)
    check calls.len == 0

  test "malformed JSON inside tags is skipped":
    let response = "<tool_call>this is not json</tool_call>"
    let calls = parseXmlToolCalls(response)
    check calls.len == 0

  test "markdown fenced JSON inside tags":
    let response = """<tool_call>
```json
{"name": "shell", "arguments": {"command": "pwd"}}
```
</tool_call>"""
    let calls = parseXmlToolCalls(response)
    check calls.len == 1
    check calls[0].name == "shell"

  test "empty arguments defaults to empty table":
    let response = """<tool_call>{"name": "shell"}</tool_call>"""
    let calls = parseXmlToolCalls(response)
    check calls.len == 1
    check calls[0].name == "shell"
    check calls[0].arguments.len == 0

  test "bracket notation TOOL_CALL":
    let response = """[TOOL_CALL]
{"name": "shell", "arguments": {"command": "echo hi"}}
[/TOOL_CALL]"""
    let calls = parseXmlToolCalls(response)
    check calls.len == 1
    check calls[0].name == "shell"

  test "unclosed tag with valid JSON recovers":
    let response = """<tool_call>{"name": "shell", "arguments": {"command": "ls"}}"""
    let calls = parseXmlToolCalls(response)
    check calls.len == 1
    check calls[0].name == "shell"

suite "XML Tool Text Extraction":
  test "extract text around tool calls":
    let response = """Before text.
<tool_call>
{"name": "shell", "arguments": {"command": "echo hi"}}
</tool_call>
After text."""
    let text = extractTextFromResponse(response)
    check "Before text." in text
    check "After text." in text
    check "<tool_call>" notin text

  test "extract text with no tool calls":
    let response = "Just plain text here."
    let text = extractTextFromResponse(response)
    check text == "Just plain text here."

suite "XML Tool Result Formatting":
  test "format single successful result":
    let results = @[XmlToolResult(name: "shell", output: "hello world", success: true)]
    let formatted = formatToolResults(results)
    check "<tool_result" in formatted
    check "shell" in formatted
    check "hello world" in formatted
    check "ok" in formatted

  test "format failed result":
    let results = @[XmlToolResult(name: "shell", output: "permission denied", success: false)]
    let formatted = formatToolResults(results)
    check "error" in formatted
    check "permission denied" in formatted

  test "format multiple results":
    let results = @[
      XmlToolResult(name: "file_read", output: "contents", success: true),
      XmlToolResult(name: "shell", output: "done", success: true)
    ]
    let formatted = formatToolResults(results)
    check "file_read" in formatted
    check "shell" in formatted

suite "XML Tool Call Detection":
  test "detects tool_call tag":
    check hasXmlToolCalls("some text <tool_call> json </tool_call>")

  test "detects TOOL_CALL bracket":
    check hasXmlToolCalls("text [TOOL_CALL] json [/TOOL_CALL]")

  test "no detection in plain text":
    check not hasXmlToolCalls("just a normal response")
