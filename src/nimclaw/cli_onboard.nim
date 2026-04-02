import std/[os, json, strutils, times, tables]
import agent/cortex, config, jsony, cli_providers, utils


proc seedWorkspace(tplDir, workspace: string) =
  ## Recursively copies the workspace structure from templates
  let source = tplDir / "workspace"
  if not dirExists(source): return
  
  echo "🌱 Seeding corporate workspace structure..."
  
  proc copyRecursive(src, dest: string) =
    createDir(dest)
    for kind, path in walkDir(src):
      let name = path.lastPathPart()
      let nextDest = dest / name
      case kind
      of pcDir:
        # Dynamic Placeholder Support
        # Directories named __name__ are treated as templates.
        # During initial seeding, we create one 'default' instance if applicable.
        var finalName = name
        if name.startsWith("__") and name.endsWith("__"):
          if name == "__team_name__": finalName = "default_squad"
          elif name == "__lab_name__": finalName = "incubation_lab"
          elif name == "__agent_name__": finalName = "lexi"
          else: discard # Keep __placeholder__ if unknown

        copyRecursive(path, dest / finalName)
      of pcFile, pcLinkToFile:
        if not fileExists(nextDest):
          var content = readFile(path)
          content = content.replace("{date}", now().format("yyyy-MM-dd"))
          writeFile(nextDest, content)
          echo "  + Created: ", nextDest.relativePath(workspace)
      else: discard

  copyRecursive(source, workspace)

proc seedGlobalTemplates(tplDir: string) =
  ## Ensures the global ~/.nimclaw/templates is populated for post-install use
  let globalTemplates = getHomeDir() / ".nimclaw" / "templates"
  if dirExists(globalTemplates): return # Already seeded
  
  if dirExists(tplDir) and tplDir != globalTemplates:
    echo "📦 Seeding global templates to ~/.nimclaw/templates..."
    copyDir(tplDir, globalTemplates)

proc runOnboardCommand*(nimclawDir: string, interactive = true, api_key = "", provider = ""): string =
  ## Guided onboarding flow for NimClaw
  let workspace = nimclawDir / "workspace"
  let graphFile = nimclawDir / "BASE.json"
  let envFile = nimclawDir / ".env"

  if fileExists(graphFile):
    return "NimClaw is already onboarded at " & nimclawDir & "\nTo reset, delete BASE.json and run this again."

  echo "🦞 Welcome to NimClaw Onboarding!"
  echo "-------------------------------"
  echo "Initializing workspace at: " & nimclawDir
  
  let tplDir = getTemplateDir()
  
  try:
    createDir(nimclawDir)
    createDir(workspace)
    
    # Provider setup
    var providerName = provider
    var apiKey = api_key
    var setupDone = false
    
    while not setupDone:
      if interactive and (apiKey == "" or providerName == ""):
        let provTplDir = tplDir / "provider"
        var available = newSeq[string]()
        if dirExists(provTplDir):
          for kind, path in walkDir(provTplDir):
            if kind == pcFile and path.endsWith(".json"):
              available.add(path.lastPathPart().changeFileExt(""))
        
        if providerName == "" and available.len > 0:
          providerName = selectInput("Please Select ↕ Or Enter a provider below.", available)
        
        while true:
          if providerName == "":
            stdout.write "Enter provider: "; providerName = stdin.readLine().strip().toLowerAscii()
          
          if providerName == "": break

          if available.len > 0 and providerName notin available:
            echo "⚠️ Provider template '" & providerName & "' not found. "
            echo "Please select from: ", available.join(", ")
            providerName = "" # Reset to re-prompt
            continue
          
          stdout.write "Enter your API key for $1 (or nothing to cancel).\n".format(providerName)
          apiKey = readMaskedInput(": ")
          if apiKey != "": break
          echo "❌ Cancelled. NimClaw setup aborted."
          return "Cancelled."
      
      if apiKey != "":
        let envContent = providerName.toUpperAscii() & "_API_KEY=" & apiKey & "\n"
        writeFile(envFile, envContent)
        echo "✅ Credentials saved to " & envFile
      
      # Merge Template and Test Connection
      if providerName != "":
        let provTplPath = tplDir / "provider" / providerName & ".json"
        if fileExists(provTplPath):
          try:
            let tData = parseFile(provTplPath)
            let defModel = tData{"defaultModel"}.getStr("")
            echo "📂 Loaded provider template for $1 with \"defaultModel\": \"$2\"".format(providerName, defModel)
            
            var pNode = %*{
              "name": tData{"name"}.getStr(providerName.capitalizeAscii()),
              "apiBase": tData{"apiBase"}.getStr(""),
              "apiKey": "${" & providerName.toUpperAscii() & "_API_KEY}"
            }
            if tData.hasKey("defaultModel"): pNode["defaultModel"] = tData["defaultModel"]
            if tData.hasKey("models"): pNode["models"] = tData["models"]
            
            # Temporary graph for testing
            let apiBase = tData{"apiBase"}.getStr("")
            
            if apiKey != "" and defModel != "":
              stdout.write "🧪 Testing connection to " & providerName & " (" & defModel & ")... "
              stdout.flushFile()
              let (ok, err) = testConnection(apiBase, apiKey, defModel)
              if ok:
                echo "✨ Online"
                setupDone = true
              else:
                echo "❌ Offline (" & err & ")"
                if interactive:
                  stdout.write "\nEnter your API key for $1 again (or nothing to cancel).\n".format(providerName)
                  let nextKey = readMaskedInput(": ")
                  if nextKey == "":
                    echo "❌ Cancelled. NimClaw setup aborted."
                    return "Cancelled."
                  else:
                    apiKey = nextKey # Retry with new key
                else:
                  setupDone = true # Non-interactive proceeds anyway
            else:
              setupDone = true
          except:
            echo "⚠️ Error during provider setup: ", getCurrentExceptionMsg()
            setupDone = true
        else:
          echo "⚠️ Provider template not found: ", provTplPath
          setupDone = true
      else:
        setupDone = true

    # 0. Seed global templates if missing (helps with global CLI usage)
    seedGlobalTemplates(tplDir)
    
    # ... (Config migration code) ...
    let legacyConfigPath = nimclawDir / "config.json"
    var initialConfig = defaultConfig()
    var migrated = false
    
    if fileExists(legacyConfigPath):
      echo "📜 Legacy config.json detected. Migrating settings..."
      try:
        initialConfig = loadConfig(legacyConfigPath)
        migrated = true
      except:
        echo "⚠️ Warning: Failed to parse legacy config.json. Using defaults."

    # 2. Seed workspace structure and standard docs
    seedWorkspace(tplDir, workspace)

    # 3. Generate default high-fidelity graph
    var graph = defaultWorldGraph(workspace)
    
    # 3b. Finalize Provider Configuration in Graph
    if providerName != "":
      graph.providers = newJObject() # Clear defaults
      let provTplPath = tplDir / "provider" / providerName & ".json"
      if fileExists(provTplPath):
        try:
          let tData = parseFile(provTplPath)
          var pNode = %*{
            "name": tData{"name"}.getStr(providerName.capitalizeAscii()),
            "apiBase": tData{"apiBase"}.getStr(""),
            "apiKey": "${" & providerName.toUpperAscii() & "_API_KEY}"
          }
          if tData.hasKey("defaultModel"): pNode["defaultModel"] = tData["defaultModel"]
          if tData.hasKey("models"): pNode["models"] = tData["models"]
          
          graph.providers[providerName] = pNode
          
          # Update Global Defaults
          let defModel = tData{"defaultModel"}.getStr("")
          if defModel != "":
            graph.config["default_provider"] = %providerName
            graph.config["default_model"] = % (providerName & "/" & defModel)
            
            # Update Lexi (nc:2)
            if tables.hasKey(graph.entities, WorldEntityID(2)):
              var lexi = graph.entities[WorldEntityID(2)]
              lexi.model = providerName & "/" & defModel
              graph.entities[WorldEntityID(2)] = lexi
              
          echo "✅ Configured provider: ", providerName
        except:
          echo "⚠️ Error finalizing provider: ", getCurrentExceptionMsg()

    graph.config = parseJson(initialConfig.toJson())
    
    let node = toLD(graph)
    writeFile(graphFile, node.pretty())

    # 4. Cleanup legacy file if migrated
    if migrated:
      try:
        removeFile(legacyConfigPath)
        echo "🗑️ Legacy config.json removed."
      except:
        echo "⚠️ Warning: Could not remove legacy config.json."

    # Create logs directory
    let logsDir = nimclawDir / "logs"
    if not dirExists(logsDir):
      createDir(logsDir)

    # Initialize structured platform directories in .nimclaw
    createDir(nimclawDir / "skills")
    createDir(nimclawDir / "plugins")

    return "\n✨ Success! NimClaw is ready.\n\n" &
           "Your unified world graph and configuration is at: " & graphFile & "\n" &
           "Try running: ./nimclaw agents list"
  except:
    return "Error during onboarding: " & getCurrentExceptionMsg()
