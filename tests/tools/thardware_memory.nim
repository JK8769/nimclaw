import std/[unittest, json, tables, strutils, asyncdispatch]
import ../../src/nimclaw/tools/[types, hardware_memory]

suite "Hardware Memory Tool Tests":
  setup:
    let boards = @["nucleo-f401re"]
    let hwTool = newHardwareMemoryTool(boards)

  test "hardware_memory tool name":
    check hwTool.name() == "hardware_memory"

  test "hardware_memory schema has action":
    let params = hwTool.parameters()
    check params["properties"].hasKey("action")
    check params["properties"].hasKey("address")

  test "hardware_memory no boards returns error":
    let t = newHardwareMemoryTool(@[])
    let args = {"action": %"read"}.toTable
    let res = waitFor t.execute(args)
    check "No peripherals configured" in res

  test "hardware_memory missing action returns error":
    let args = initTable[string, JsonNode]()
    let res = waitFor hwTool.execute(args)
    check "action" in res

  test "hardware_memory unsupported board":
    let t = newHardwareMemoryTool(@["esp32"])
    let args = {"action": %"read", "board": %"esp32"}.toTable
    let res = waitFor t.execute(args)
    check "nucleo" in res

  test "hardware_memory read without probe-rs":
    let args = {"action": %"read", "address": %"0x20000000", "length": %64}.toTable
    let res = waitFor hwTool.execute(args)
    # the test is simply that this doesn't crash or throw. It will either say probe-rs not found,
    # or it will say probe-rs read failed, or it'll succeed if a device is connected.
    check res.len > 0

  test "hardware_memory write missing value":
    let args = {"action": %"write", "address": %"0x20000000"}.toTable
    let res = waitFor hwTool.execute(args)
    check "value" in res

  test "hardware_memory unknown action":
    let args = {"action": %"delete"}.toTable
    let res = waitFor hwTool.execute(args)
    check "Unknown action" in res
