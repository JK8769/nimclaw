import std/[asyncdispatch, json, tables, os, strutils]
import ../src/nimclaw/skills/loader

proc verifyLoader() =
  echo "--- Verifying Loader with Phase 400 changes ---"
  
  let workspace = "/tmp/nimclaw_workspace"
  let globalSkills = getHomeDir() / ".nimclaw" / "skills"
  createDir(workspace / "skills")
  
  let sl = newSkillsLoader(workspace, globalSkills, "")
  
  echo "[1] Listing skills..."
  let skills = sl.listSkills()
  var foundTestSkill = false
  for s in skills:
    echo "Skill: ", s.name, " Source: ", s.source, " Requires: ", s.requires_tools
    if s.name == "test_skill":
      foundTestSkill = true
      if s.source == "global":
        echo "SUCCESS: Found test_skill in global location."
      else:
        echo "FAILURE: test_skill source is NOT global."
      
      if "test_tool" in s.requires_tools and "filesystem" in s.requires_tools:
        echo "SUCCESS: Successfully parsed requires_tools."
      else:
        echo "FAILURE: Parsing requires_tools failed."
        
  if not foundTestSkill:
    echo "FAILURE: test_skill NOT found in listing."

  echo "\n[2] Loading skill content..."
  let (content, ok) = sl.loadSkill("test_skill")
  if ok:
    echo "SUCCESS: Skill content loaded."
    if "# Test Skill Content" in content:
      echo "SUCCESS: Content is correct."
    else:
      echo "FAILURE: Content is NOT correct."
  else:
    echo "FAILURE: Skill loading failed."

  echo "\n--- Verification Complete ---"

verifyLoader()
