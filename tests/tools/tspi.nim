import std/[unittest, json, tables, strutils, asyncdispatch]
import ../../src/nimclaw/tools/[types, spi]

suite "SPI Tool Tests":
  setup:
    let st = newSpiTool()

  test "spi tool name":
    check st.name() == "spi"

  test "spi tool description not empty":
    check st.description().len > 0

  test "spi tool schema has action":
    let params = st.parameters()
    check params["properties"].hasKey("action")
    check params["properties"].hasKey("device")
    check params["properties"].hasKey("speed_hz")

  test "spi missing action":
    let args = initTable[string, JsonNode]()
    let res = waitFor st.execute(args)
    check "action" in res

  test "spi unknown action":
    let args = {"action": %"unknown"}.toTable
    let res = waitFor st.execute(args)
    when not defined(linux):
      check "not supported" in res
    else:
      check "Unknown action" in res

  test "spi list action on non-linux":
    when not defined(linux):
      let args = {"action": %"list"}.toTable
      let res = waitFor st.execute(args)
      check "not supported" in res

  test "spi transfer on non-linux returns error":
    when not defined(linux):
      let args = {"action": %"transfer", "data": %"FF 0A"}.toTable
      let res = waitFor st.execute(args)
      check "not supported" in res

  test "spi read on non-linux returns error":
    when not defined(linux):
      let args = {"action": %"read"}.toTable
      let res = waitFor st.execute(args)
      check "not supported" in res
