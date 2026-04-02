import std/[asyncdispatch, json, tables, os, strutils, times]
import ../src/nimclaw/tools/persist, ../src/nimclaw/tools/registry, ../src/nimclaw/tools/types

proc verifyPhase400() {.async.} =
  echo "--- Verifying Phase 400 Persistence ---"
  
  let reg = newToolRegistry()
  let persistTool = newPersistTool(reg)
  let persistSkillTool = newPersistSkillTool(reg)
  
  # 1. Test persist_mcp_tool
  echo "[1] Testing persist_mcp_tool..."
  let mcpArgs = {
    "name": %"test_tool",
    "version": %"1.2.3",
    "comment": %"Verified persistence logic"
  }.toTable
  
  let mcpRes = await persistTool.execute(mcpArgs)
  echo "MCP Promotion Result: ", mcpRes
  
  let targetDir = getHomeDir() / ".nimclaw" / "mcp" / "tools" / "test_tool"
  let targetSrc = targetDir / "test_tool.nim"
  let targetBin = targetDir / "test_tool"
  
  if dirExists(targetDir) and fileExists(targetSrc) and fileExists(targetBin):
    echo "SUCCESS: MCP tool promoted to ", targetDir
    let srcContent = readFile(targetSrc)
    if "Version: 1.2.3" in srcContent and "Verified persistence logic" in srcContent:
      echo "SUCCESS: Version history injected into source."
    else:
      echo "FAILURE: Version history NOT found in source."
  else:
    echo "FAILURE: MCP tool promotion failed. Dir: ", dirExists(targetDir), " Src: ", fileExists(targetSrc), " Bin: ", fileExists(targetBin)

  # 2. Test persist_skill
  echo "\n[2] Testing persist_skill..."
  let skillSourceDir = "/tmp/test_skill_source"
  createDir(skillSourceDir)
  writeFile(skillSourceDir / "SKILL.md", "---\nname: Test Skill\ndescription: A test skill\nrequires_tools: test_tool, filesystem\n---\n# Test Skill Content")
  
  let skillArgs = {
    "skill_name": %"test_skill",
    "source_path": %skillSourceDir
  }.toTable
  
  let skillRes = await persistSkillTool.execute(skillArgs)
  echo "Skill Promotion Result: ", skillRes
  
  let targetSkillDir = getHomeDir() / ".nimclaw" / "skills" / "test_skill"
  if dirExists(targetSkillDir) and fileExists(targetSkillDir / "SKILL.md"):
    echo "SUCCESS: Skill promoted to ", targetSkillDir
  else:
    echo "FAILURE: Skill promotion failed."

  echo "\n--- Verification Complete ---"

waitFor verifyPhase400()
