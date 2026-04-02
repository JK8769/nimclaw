import std/[asyncdispatch, json, tables, strutils]
import types
import ../skills/installer

type
  SkillInstallTool* = ref object of Tool
    installer: SkillInstaller

proc newSkillInstallTool*(installer: SkillInstaller): SkillInstallTool =
  SkillInstallTool(installer: installer)

method name*(t: SkillInstallTool): string = "install_skill"

method description*(t: SkillInstallTool): string =
  "Download and install a skill from a URL (e.g., GitHub or personal site). Provide a full URL or 'owner/repo' shorthand for GitHub."

method parameters*(t: SkillInstallTool): Table[string, JsonNode] =
  {
    "type": %"object",
    "properties": %*{
      "repository": {
        "type": "string",
        "description": "The URL or 'owner/repo' shorthand of the skill to install."
      },
      "acquisition_method": {
        "type": "string",
        "enum": ["auto", "git", "download"],
        "description": "Optional: Explicitly choose how to fetch the skill. 'git' clones the repo, 'download' fetches a single file (SKILL.md). Defaults to 'auto'.",
        "default": "auto"
      },
      "sub_path": {
        "type": "string",
        "description": "Optional: A specific subdirectory or file within the repository to install as the skill (e.g., 'skills/frontend-design')."
      }
    },
    "required": %["repository"]
  }.toTable

method execute*(t: SkillInstallTool, args: Table[string, JsonNode]): Future[string] {.async.} =
  if not args.hasKey("repository"):
    return "Error: Missing 'repository' parameter."

  let repo = args["repository"].getStr().strip()
  if repo.len == 0:
    return "Error: Repository path cannot be empty."
    
  let mode = if args.hasKey("acquisition_method"): args["acquisition_method"].getStr() else: "auto"
  let subPath = if args.hasKey("sub_path"): args["sub_path"].getStr() else: ""

  try:
    await t.installer.installFromGitHub(repo, mode, subPath)
    return "Successfully installed skill from: " & repo & " (mode: " & mode & ", sub_path: " & subPath & ")"
  except Exception as e:
    return "Error installing skill: " & e.msg
