import std/[json, strutils, tables]
import nimclaw/agent/xml_tools

let response = """让我使用标准的 MCP 模板格式再试一次：

<tool_call>
  <name>forge_mcp_tool</name>
  <arguments>
    <name>nim_analyzer</name>
    <description>分析 Nim 代码的工具</description>
    <code>
import mcp
import std/os

mcpServer:
  tool "analyze", "Analyze nim file":
    let path = getStr(arguments, "path")
    # Using some < and > characters to test robustness
    if path.len > 0 and path.len < 100:
      result = %* {"content": readFile(path)}

runServer()
    </code>
  </arguments>
</tool_call>"""

echo "--- Testing Response ---"
echo response
echo "------------------------"

let tools = parseXmlToolCalls(response)
echo "Found tools: ", tools.len

if tools.len == 0:
  echo "FAILED TO PARSE TOOLS"
else:
  for t in tools:
    echo "Tool: ", t.name
    echo "Args: ", t.arguments
