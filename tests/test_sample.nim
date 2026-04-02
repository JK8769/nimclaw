# Test file for nim_check
import std/strutils

proc greet(name: string): string =
  result = "Hello, " & name & "!"

echo greet("MCP")
