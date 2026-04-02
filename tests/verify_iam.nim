import std/[asyncdispatch, json, tables, os, strutils]
import ../src/nimclaw/tools/[types, registry]

# Mock Tool for testing
type MockTool = ref object of Tool
method name*(t: MockTool): string = "exec"
method description*(t: MockTool): string = "Mock exec tool"
method parameters*(t: MockTool): Table[string, JsonNode] = initTable[string, JsonNode]()
method execute*(t: MockTool, args: Table[string, JsonNode]): Future[string] {.async.} = return "Executed Successfully"

proc testIAM() {.async.} =
  let tr = newToolRegistry()
  tr.register(MockTool())
  
  echo "--- IAM Verification Test ---"
  
  # 1. Test unauthorized access (Secretary trying to use 'exec')
  echo "Testing: Secretary role using 'exec' tool..."
  let result1 = await tr.executeWithContext("exec", initTable[string, JsonNode](), "test", "test", "session", "user", "Lexi", role = "Secretary")
  if result1.find("Unauthorized") != -1:
    echo "✅ SUCCESS: Unauthorized access blocked correctly."
  else:
    echo "❌ FAILURE: Unauthorized access was NOT blocked."
    echo "   Result: ", result1

  # 2. Test authorized access (Tech Lead using 'exec')
  echo "Testing: Tech Lead role using 'exec' tool..."
  let result2 = await tr.executeWithContext("exec", initTable[string, JsonNode](), "test", "test", "session", "user", "Robin", role = "Tech Lead")
  if result2 == "Executed Successfully":
    echo "✅ SUCCESS: Authorized access allowed correctly."
  else:
    echo "❌ FAILURE: Authorized access was blocked."
    echo "   Result: ", result2

  echo "--- Test Complete ---"

waitFor testIAM()
