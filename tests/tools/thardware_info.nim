import std/[unittest, json, tables, strutils, asyncdispatch]
import ../../src/nimclaw/tools/[types, hardware_info]

suite "Hardware Info Tool Tests":
  setup:
    let boards = @["nucleo-f401re"]
    let hwTool = newHardwareBoardInfoTool(boards)
  
  test "hardware_board_info tool name":
    check hwTool.name() == "hardware_board_info"

  test "hardware_board_info tool description not empty":
    check hwTool.description().len > 0

  test "hardware_board_info schema has board":
    let params = hwTool.parameters()
    check params["properties"].hasKey("board")

  test "hardware_board_info no boards returns error":
    let emptyTool = newHardwareBoardInfoTool(@[])
    let args = initTable[string, JsonNode]()
    let res = waitFor emptyTool.execute(args)
    check "No peripherals configured" in res

  test "hardware_board_info known board returns info":
    let args = {"board": %"nucleo-f401re"}.toTable
    let res = waitFor hwTool.execute(args)
    check "STM32F401" in res
    check "Memory map" in res

  test "hardware_board_info default board from config":
    let args = initTable[string, JsonNode]()
    let res = waitFor hwTool.execute(args)
    check "STM32F401" in res

  test "hardware_board_info unknown board returns message":
    let customTool = newHardwareBoardInfoTool(@["custom-board"])
    let args = {"board": %"custom-board"}.toTable
    let res = waitFor customTool.execute(args)
    check "custom-board" in res
    check "No static info available" in res

  test "hardware_board_info esp32":
    let espTool = newHardwareBoardInfoTool(@["esp32"])
    let args = {"board": %"esp32"}.toTable
    let res = waitFor espTool.execute(args)
    check "ESP32" in res
