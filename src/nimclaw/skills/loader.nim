import std/[os, strutils, sequtils]
import openclaw_compat, skill_types



type
  SkillsLoader* = ref object
    workspace*: string
    projectCompetencies*: string
    privateSkills*: string
    globalSkills*: string
    builtinSkills*: string
    openClawExtensions*: string

proc newSkillsLoader*(workspace, projectCompetencies, privateSkills, globalSkills, builtinSkills, openClawExtensions: string): SkillsLoader =
  SkillsLoader(
    workspace: workspace,
    projectCompetencies: projectCompetencies,
    privateSkills: privateSkills,
    globalSkills: globalSkills,
    builtinSkills: builtinSkills,
    openClawExtensions: openClawExtensions
  )

proc parseFrontmatter(content: string): SkillMetadata =
  ## Simple YAML frontmatter parser for name: and description:
  result = SkillMetadata()
  if content.startsWith("---\n"):
    let nextIdx = content.find("\n---\n", 4)
    if nextIdx != -1:
      let fm = content[4 .. nextIdx]
      for line in fm.splitLines():
        let parts = line.split(":", 1)
        if parts.len == 2:
          let key = parts[0].strip().toLowerAscii()
          let val = parts[1].strip()
          if key == "name": result.name = val
          elif key == "description": result.description = val
          elif key == "requires_tools":
            result.requires_tools = val.split(",").mapIt(it.strip())

proc getSkillMetadata(sl: SkillsLoader, dir: string): SkillMetadata =
  ## Extract metadata from SKILL.md or openclaw.plugin.json.
  let skillFile = dir / "SKILL.md"
  let pluginFile = dir / "openclaw.plugin.json"

  if fileExists(skillFile):
    let content = readFile(skillFile)
    result = parseFrontmatter(content)
  elif fileExists(pluginFile):
    let content = readFile(pluginFile)
    result = parseOpenClawManifest(content)
  
  if result.name == "":
    result.name = lastPathPart(dir)

proc escapeXML(s: string): string =
  s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

proc stripFrontmatter(content: string): string =
  # Simple version: if it starts with ---, find next ---
  if content.startsWith("---\n"):
    let nextIdx = content.find("\n---\n", 4)
    if nextIdx != -1:
      return content[nextIdx + 5 .. ^1]
  return content

proc listSkills*(sl: SkillsLoader): seq[SkillInfo] =
  ## Lists all skills from workspace, global, and OpenClaw extension directories.
  result = @[]

  proc findSkillsRecursive(dir: string, source: string, results: var seq[SkillInfo], depth: int) =
    if not dirExists(dir) or depth > 3: return
    
    let skillFile = dir / "SKILL.md"
    let pluginFile = dir / "openclaw.plugin.json"
    
    if fileExists(skillFile) or fileExists(pluginFile):
      let meta = sl.getSkillMetadata(dir)
      let primaryFile = if fileExists(skillFile): skillFile else: pluginFile
      let sanitizedName = meta.name.replace("-", "_")
      results.add(SkillInfo(
        name: sanitizedName,
        path: primaryFile,
        source: source,
        description: meta.description,
        location: absolutePath(dir),
        requires_tools: meta.requires_tools
      ))
      # If we found a skill/plugin, we don't necessarily stop, 
      # but usually subdirs won't contain more skills unless it's a "skills" folder
      
    for kind, path in walkDir(dir):
      if kind == pcDir:
        let base = lastPathPart(path)
        if base == "node_modules" or base.startsWith("."): continue
        findSkillsRecursive(path, source, results, depth + 1)

  # Discovery locations
  findSkillsRecursive(sl.privateSkills, "private", result, 0)
  findSkillsRecursive(sl.projectCompetencies, "workspace", result, 0)
  findSkillsRecursive(sl.builtinSkills, "builtin", result, 0)
  
  # Platform-level structured discovery
  findSkillsRecursive(sl.globalSkills / "skills", "platform", result, 0)
  findSkillsRecursive(sl.globalSkills / "plugins", "platform", result, 0)
  findSkillsRecursive(sl.globalSkills, "global", result, 0)

  # OpenClaw Extensions
  if sl.openClawExtensions != "":
    findSkillsRecursive(sl.openClawExtensions, "openclaw", result, 0)

proc loadSkill*(sl: SkillsLoader, name: string): (string, bool) =
  ## Loads a specific skill by name, searching through all discovered skills.
  let skills = sl.listSkills()
  for s in skills:
    if s.name == name or lastPathPart(s.path) == name:
      return (readFile(s.path).stripFrontmatter(), true)
  return ("", false)

proc loadSkillsForContext*(sl: SkillsLoader, skillNames: seq[string]): string =
  if skillNames.len == 0: return ""
  var parts: seq[string] = @[]
  for name in skillNames:
    let (content, ok) = sl.loadSkill(name)
    if ok:
      parts.add("### Skill: " & name & "\n\n" & content)
  return parts.join("\n\n---\n\n")


proc buildSkillsSummary*(sl: SkillsLoader): string =
  let skills = sl.listSkills()
  if skills.len == 0: return ""
  var lines = @["<skills>"]
  for s in skills:
    lines.add("  <skill>")
    lines.add("    <name>" & escapeXML(s.name) & "</name>")
    lines.add("    <description>" & escapeXML(s.description) & "</description>")
    lines.add("    <location>" & escapeXML(s.location) & "</location>")
    lines.add("    <source>" & s.source & "</source>")
    if s.requires_tools.len > 0:
      lines.add("    <requires_tools>" & s.requires_tools.join(", ") & "</requires_tools>")
    lines.add("  </skill>")
  lines.add("</skills>")
  return lines.join("\n")
