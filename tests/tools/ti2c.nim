import std/[unittest, json, tables, strutils, asyncdispatch]
import ../../src/nimclaw/tools/[types, i2c]

suite "I2C Tool Tests":
  setup:
    let i2cTool = newI2cTool()

  test "i2c tool name":
    check i2cTool.name() == "i2c"

  test "i2c tool description not empty":
    check i2cTool.description().len > 0

  test "i2c tool schema has action":
    let params = i2cTool.parameters()
    check params["properties"].hasKey("action")
    check params["properties"].hasKey("bus")
    check params["properties"].hasKey("address")
    check params["properties"].hasKey("register")

  test "i2c missing action parameter":
    let args = initTable[string, JsonNode]()
    let res = waitFor i2cTool.execute(args)
    check "action" in res

  test "i2c unknown action":
    let args = {"action": %"reset"}.toTable
    let res = waitFor i2cTool.execute(args)
    when not defined(linux):
      check "not supported" in res
    else:
      check "Unknown action" in res

  test "i2c detect on non-linux returns platform error":
    when not defined(linux):
      let args = {"action": %"detect"}.toTable
      let res = waitFor i2cTool.execute(args)
      check "not supported" in res

  test "i2c scan on non-linux returns platform error":
    when not defined(linux):
      let args = {"action": %"scan", "bus": %1}.toTable
      let res = waitFor i2cTool.execute(args)
      check "not supported" in res

  test "i2c read on non-linux returns platform error":
    when not defined(linux):
      let args = {"action": %"read", "bus": %1, "address": %"0x48", "register": %0}.toTable
      let res = waitFor i2cTool.execute(args)
      check "not supported" in res

  test "i2c write on non-linux returns platform error":
    when not defined(linux):
      let args = {"action": %"write", "bus": %1, "address": %"0x48", "register": %0, "value": %42}.toTable
      let res = waitFor i2cTool.execute(args)
      check "not supported" in res

  test "i2c scan missing bus parameter":
    when not defined(linux):
      let args = {"action": %"scan"}.toTable
      let res = waitFor i2cTool.execute(args)
      check "not supported" in res
