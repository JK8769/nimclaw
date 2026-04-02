import std/[asyncdispatch, httpclient, os, json, strutils, osproc]

type
  AvailableSkill* = object
    name*: string
    repository*: string
    description*: string
    author*: string
    tags*: seq[string]

  BuiltinSkill* = object
    name*: string
    path*: string
    enabled*: bool

  SkillInstaller* = ref object
    workspace*: string

proc newSkillInstaller*(workspace: string): SkillInstaller =
  SkillInstaller(workspace: workspace)

proc installFromGitHub*(si: SkillInstaller, repo: string, mode: string = "auto", subPath: string = ""): Future[void] {.async.} =
  var repoUrl = repo
  var actualSubPath = subPath
  var skillName = ""
  
  # Handle --skill flag in the repo string if present
  if " --skill " in repo:
    let parts = repo.split(" --skill ")
    repoUrl = parts[0].strip()
    actualSubPath = parts[1].strip()

  var isGithubFile = repoUrl.contains("blob/") or repoUrl.contains("raw/")

  if repoUrl.startsWith("https://github.com/") and not isGithubFile:
    skillName = lastPathPart(repoUrl)
    if skillName.endsWith(".git"): skillName = skillName[0..^5]
    if actualSubPath.len > 0:
      # If subPath is provided, make skillName more specific
      skillName = skillName & "-" & lastPathPart(actualSubPath)
  elif "/" in repoUrl and not repoUrl.contains("://"):
    repoUrl = "https://github.com/" & repoUrl
    skillName = lastPathPart(repoUrl)
    if actualSubPath.len > 0:
      skillName = skillName & "-" & lastPathPart(actualSubPath)
  else:
    # Generic URL or GitHub file
    let parts = repoUrl.split("://")
    if parts.len > 1:
      let pathParts = parts[1].split("/")
      if pathParts.len > 1:
        let host = pathParts[0].replace(".", "-")
        let filename = pathParts[^1].replace(".md", "").replace(".zip", "")
        if filename == "skill" or filename == "SKILL":
          skillName = host & "-" & filename
        else:
          skillName = filename
      else:
        skillName = lastPathPart(repoUrl).replace(".md", "")
    else:
      skillName = lastPathPart(repoUrl).replace(".md", "")

  let skillDir = si.workspace / "skills" / skillName

  if dirExists(skillDir):
    echo "ℹ️ Skill '$1' is already installed.".format(skillName)
    return

  if not dirExists(si.workspace / "skills"):
    createDir(si.workspace / "skills")

  var currentMode = mode
  if isGithubFile and currentMode == "auto":
    currentMode = "download"

  var gitSuccess = false
  if currentMode == "auto" or currentMode == "git":
    # 1. Try Git Clone
    echo "Attempting to clone repository: ", repoUrl
    let gitExitCode = execCmd("git clone --depth 1 $1 $2".format(repoUrl, skillDir))
    
    if gitExitCode == 0:
      echo "[SUCCESS] Skill cloned via Git."
      gitSuccess = true
      
      # Handle subPath extraction if specified
      if actualSubPath.len > 0:
        let fullSubPath = skillDir / actualSubPath
        if dirExists(fullSubPath):
          echo "Extracting sub-path: ", actualSubPath
          let tempDir = getTempDir() / "nimclaw_skill_extract_" & $getCurrentProcessId()
          createDir(tempDir)
          copyDir(fullSubPath, tempDir)
          removeDir(skillDir)
          createDir(skillDir)
          copyDir(tempDir, skillDir)
          removeDir(tempDir)
        elif fileExists(fullSubPath):
          echo "Extracting single file from sub-path: ", actualSubPath
          let tempFile = getTempDir() / "SKILL.md"
          copyFile(fullSubPath, tempFile)
          removeDir(skillDir)
          createDir(skillDir)
          moveFile(tempFile, skillDir / "SKILL.md")
        else:
          echo "⚠️ Warning: sub_path '$1' not found in repository.".format(actualSubPath)
    elif currentMode == "git":
      raise newException(IOError, "Git clone failed for repository: " & repoUrl)
    else:
      echo "Git clone failed or git missing. Falling back to direct download..."

  if not gitSuccess and (currentMode == "auto" or currentMode == "download"):
    # 2. Fallback to direct SKILL.md download (for single-file skills or missing git)
    var downloadUrl = repoUrl
    if not repoUrl.contains("://"):
      downloadUrl = "https://raw.githubusercontent.com/$1/main/SKILL.md".format(repoUrl)
    elif repoUrl.startsWith("https://github.com/"):
      downloadUrl = repoUrl.replace("github.com", "raw.githubusercontent.com") & "/main/SKILL.md"

    let client = newAsyncHttpClient()
    try:
      let response = await client.get(downloadUrl)
      if response.status != $Http200:
        # Try 'master' as a last resort
        let masterUrl = downloadUrl.replace("/main/", "/master/")
        let masterResp = await client.get(masterUrl)
        if masterResp.status != $Http200:
          raise newException(IOError, "Failed to fetch skill (tried main and master): " & response.status)
        
        let body = await masterResp.body
        createDir(skillDir)
        writeFile(skillDir / "SKILL.md", body)
      else:
        let body = await response.body
        createDir(skillDir)
        writeFile(skillDir / "SKILL.md", body)
      
      echo "[SUCCESS] Skill downloaded directly."
    finally:
      client.close()

proc uninstall*(si: SkillInstaller, skillName: string) =
  let skillDir = si.workspace / "skills" / skillName
  if not dirExists(skillDir):
    raise newException(IOError, "Skill '$1' not found".format(skillName))
  removeDir(skillDir)

proc listAvailableSkills*(si: SkillInstaller): Future[seq[AvailableSkill]] {.async.} =
  let url = "https://raw.githubusercontent.com/sipeed/nimclaw-skills/main/skills.json"
  let client = newAsyncHttpClient()

  try:
    let response = await client.get(url)
    if response.status != $Http200:
      raise newException(IOError, "Failed to fetch skills list: " & response.status)

    let body = await response.body
    return parseJson(body).to(seq[AvailableSkill])
  finally:
    client.close()
