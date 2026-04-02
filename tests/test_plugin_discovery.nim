import std/[os, strutils]
import src/nimclaw/config
import src/nimclaw/skills/loader
import src/nimclaw/agent/context

echo "🧪 OpenClaw Plugin Discovery Test"
echo "-------------------------------"

let workspace = getCurrentDir()
let cb = newContextBuilder(workspace)

let skills = cb.skillsLoader.listSkills()
echo "Discovered ", skills.len, " skills total."

var larkFound = false
for s in skills:
  if s.name.contains("feishu") or s.name.contains("lark"):
    echo "✅ Found OpenClaw Skill: ", s.name, " (", s.source, ")"
    echo "   Location: ", s.location
    larkFound = true

if not larkFound:
  echo "❌ No OpenClaw Lark skills found."
  echo "Extensions Dir searched: ", cb.skillsLoader.openClawExtensions
else:
  echo "\n✨ Success! OpenClaw plugins are being discovered recursively."
