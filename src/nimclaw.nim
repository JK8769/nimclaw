import std/[os, strutils, asyncdispatch, tables, posix, exitprocs, json, algorithm]
import cligen
import curly, webby/httpheaders
import nimclaw/[config, logger, bus, bus_types, session, agent/loop, agent/cortex, providers/http, providers/types as providers_types, doctor, cli_service]
import nimclaw/channels/[manager as channel_manager]
import nimclaw/services/[heartbeat, cron as cron_service]
import nimclaw/version as version_mod

const logo = "🦞🦞🦞"

proc version*() =
  ## Print the nimclaw version
  echo "nimclaw ", version_mod.versionString()

proc doctor_cmd*(color: bool = true) =
  ## Check system configuration and health status
  putEnv("NO_COLOR", if not color: "1" else: "")
  doctor.runDoctor(loadConfig(getConfigPath()), color)



type
  GatewayContext = ref object
    cfg: Config
    msgBus: MessageBus
    provider: LLMProvider
    cronService: CronService
    offices: Table[string, AgentLoop]

var gCtx: GatewayContext = nil
var gChanManager: channel_manager.Manager = nil
var isShuttingDown = false

proc gracefulShutdown() =
  if isShuttingDown: return
  isShuttingDown = true
  echo "\n[GATEWAY] Shutting down gracefully..."
  if gCtx != nil:
    # Stop all office threads/MCPs
    for office in gCtx.offices.values:
      try: office.stop()
      except: discard
  
  if gChanManager != nil:
    # Stop channel bridges
    waitFor gChanManager.stopAll()
  echo "[GATEWAY] Shutdown complete. Goodbye! 🦞"

proc cronHandlerLogic(job: cron_service.CronJob) {.async.} =
  if gCtx == nil:
    errorCF("cronHandler", "Global context is nil", initTable[string, string]())
    return

  debugCF("cronHandler", "Triggering job", {"id": job.id}.toTable)

  let agentName = if job.payload.agentName != "": job.payload.agentName else: "Lexi"
  let officeKey = agentName.toLowerAscii()

  if job.payload.deliver:
    gCtx.msgBus.publishOutbound(newOutbound(job.payload.channel, agentName, job.payload.to, job.payload.message))
  else:
    if not gCtx.offices.hasKey(officeKey):
      gCtx.offices[officeKey] = newAgentLoop(gCtx.cfg, gCtx.msgBus, gCtx.provider, agentName, gCtx.cronService)

    let sender = if job.payload.senderID != "": job.payload.senderID else: "system:scheduler"
    let agentResponse = await gCtx.offices[officeKey].processDirect(job.payload.message, sender, sender, channel = job.payload.channel)

    if agentResponse != "":
      gCtx.msgBus.publishOutbound(newOutbound(job.payload.channel, agentName, job.payload.to, agentResponse))

proc cronHandler(job: cron_service.CronJob): Future[void] =
  return cronHandlerLogic(job)

proc handleSystemCommand(cfg: ref Config, msg: InboundMessage, al: AgentLoop): Future[string] {.async.} =
  let cmd = msg.content.strip()
  if cmd == "/status":
    return "🤖 **System Status**\n" &
           "- Session: `" & msg.session_key & "`\n" &
           "- Model: `" & al.model & "`\n" &
           "- Intermediary Stream: " & (if cfg.agents.defaults.stream_intermediary: "✅ ON" else: "❌ OFF")
  elif cmd in ["/reset", "/new"]:
    al.sessions.clearSession(msg.session_key)
    return "🧹 Session history cleared for `" & msg.session_key & "`. Starting fresh!"
  elif cmd.startsWith("/stream "):
    let val = cmd.replace("/stream ", "").strip().toLowerAscii()
    if val in ["on", "true", "1"]:
      cfg.agents.defaults.stream_intermediary = true
      saveConfig(getConfigPath(), cfg[])
      return "✅ Intermediary thought streaming enabled and saved to config."
    elif val in ["off", "false", "0"]:
      cfg.agents.defaults.stream_intermediary = false
      saveConfig(getConfigPath(), cfg[])
      return "❌ Intermediary thought streaming disabled and saved to config."
    else:
      return "⚠️ Invalid stream value. Use: `/stream on` or `/stream off`."
  elif cmd.startsWith("/model"):
    let parts = cmd.split(" ", 1)
    if parts.len < 2 or parts[1].strip().len == 0:
      var msg = "Current model: `" & al.model & "` (provider: `" & cfg.default_provider & "`)\n\n"
      let graph = loadWorld(cfg[].workspacePath())
      if graph.providers != nil and graph.providers.kind == JObject and graph.providers.len > 0:
        for key, pNode in graph.providers.getFields():
          let rawKey = pNode{"apiKey"}.getStr("")
          let hasKey = if rawKey.len > 0: "✓" else: "✗"
          msg &= "**" & key & "** " & hasKey & "\n"
          if pNode.hasKey("models") and pNode["models"].kind == JArray:
            for m in pNode["models"]:
              let modelId = m.getStr()
              let marker = if modelId == al.model: " ← current" else: ""
              msg &= "  `" & key & ":" & modelId & "`" & marker & "\n"
          else:
            msg &= "  (no models listed)\n"
      msg &= "\nUsage: `/model <provider:model>`\n  `/model list <provider>` — query models from API"
      return msg
    let modelStr = parts[1].strip()

    # /model list [provider] — query models from provider API
    if modelStr == "list" or modelStr.startsWith("list "):
      let listParts = modelStr.split(" ", 1)
      let listProvider = if listParts.len > 1: listParts[1].strip() else: cfg.default_provider
      let graph = loadWorld(cfg[].workspacePath())
      let tech = resolveProviderTech("", listProvider, graph.providers, providerOverride = listProvider)
      if tech.apiBase == "":
        return "❌ No API base URL for provider `" & listProvider & "`"
      if tech.apiKey == "":
        return "❌ No API key for provider `" & listProvider & "`"
      try:
        let c = newCurly()
        var headers = emptyHttpHeaders()
        headers["Authorization"] = "Bearer " & tech.apiKey
        let resp = c.get(tech.apiBase & "/models", headers)
        if resp.code < 200 or resp.code >= 300:
          return "❌ Failed to list models from `" & listProvider & "`: HTTP " & $resp.code
        let j = parseJson(resp.body)
        var models: seq[string] = @[]
        if j.hasKey("data") and j["data"].kind == JArray:
          for m in j["data"]:
            models.add(m{"id"}.getStr())
        if models.len == 0:
          return "No models found for `" & listProvider & "`"
        models.sort()
        var msg = "**Models for `" & listProvider & "`** (" & $models.len & "):\n"
        for m in models:
          msg &= "  `" & listProvider & ":" & m & "`\n"
        return msg
      except Exception as e:
        return "❌ Error listing models: " & e.msg

    # Parse provider:model or provider/model
    var providerKey, modelName: string
    let colonPos = modelStr.find(':')
    if colonPos > 0:
      providerKey = modelStr[0..<colonPos]
      modelName = modelStr[colonPos+1..^1]
    else:
      let slashPos = modelStr.find('/')
      if slashPos < 0:
        providerKey = cfg.default_provider
        modelName = modelStr
      else:
        providerKey = modelStr[0..<slashPos]
        modelName = modelStr[slashPos+1..^1]

    # Resolve provider credentials
    let graph = loadWorld(cfg[].workspacePath())
    let tech = resolveProviderTech(modelName, providerKey, graph.providers, providerOverride = providerKey)
    if tech.apiKey == "":
      return "❌ No API key found for provider `" & providerKey & "`. Check BASE.json providers section."

    # Update agent loop at runtime
    al.provider = createProvider(tech.model, tech.apiKey, tech.apiBase)
    al.model = modelName
    cfg.default_provider = providerKey
    cfg.default_model = modelName
    cfg.agents.defaults.model = modelName

    # Update all offices with new provider
    if gCtx != nil:
      for key, office in gCtx.offices:
        office.provider = al.provider
        office.model = modelName

    # Persist to BASE.json
    let graphFile = getConfigPath().parentDir() / "BASE.json"
    if fileExists(graphFile):
      var base = parseFile(graphFile)
      base["config"]["default_provider"] = %providerKey
      base["config"]["default_model"] = %modelName
      base["config"]["agents"]["defaults"]["model"] = %modelName
      if base["config"]["agents"].hasKey("named"):
        for i in 0..<base["config"]["agents"]["named"].len:
          base["config"]["agents"]["named"][i]["provider"] = %providerKey
          base["config"]["agents"]["named"][i]["model"] = %modelName
      writeFile(graphFile, base.pretty(4))

    # Clear session for fresh start
    al.sessions.clearSession(msg.session_key)

    return "✅ Switched to `" & providerKey & "/" & modelName & "`\nSession cleared. Ready!"
  return ""

proc gateway*(args: seq[string], debug = false, host = "127.0.0.1", port = 3000, stream = true) =
  ## Start, kill or restart the long-running runtime gateway
  if debug: setLevel(DEBUG)
  
  let action = if args.len > 0: args[0] else: "run"
  let pidPath = getGatewayPidPath()
  
  case action:
  of "kill":
    discard killGateway()
    return
  of "new":
    echo "Restarting gateway..."
    discard killGateway()
  of "run":
    if fileExists(pidPath):
      try:
        let oldPid = readFile(pidPath).strip().parseInt()
        if isProcessAlive(oldPid):
          echo "❌ Error: Gateway is already running (PID: ", oldPid, ")"
          echo "Use 'nimclaw service stop' to stop it, or 'nimclaw service restart' to restart."
          quit(1)
      except:
        discard 
  else:
    echo "Unknown action: ", action, " (use run, kill, or new)"
    return

  try:
    let myPid = getpid()
    writeFile(pidPath, $myPid)
    addExitProc(proc() {.noconv.} = 
      let pPath = getNimClawDir() / "gateway.pid"
      if fileExists(pPath):
        try:
          let fPid = readFile(pPath).strip().parseInt()
          if fPid == getpid(): removeFile(pPath)
        except: discard
    )
  except:
    errorCF("gateway", "Failed to write PID file", {"error": getCurrentExceptionMsg()}.toTable)

  let logsDir = getNimClawDir() / "logs"
  if not dirExists(logsDir):
    try: createDir(logsDir)
    except: discard
  discard enableFileLogging(logsDir / "gateway.log")
  infoCF("gateway", "Starting", {"host": host, "port": $port}.toTable)
  var cfg = new(Config)
  cfg[] = loadConfig(getConfigPath())
  cfg.agents.defaults.stream_intermediary = stream
  let graph = loadWorld(cfg[].workspacePath())
  
  let tech = resolveProviderTech(cfg.agents.defaults.model, cfg.default_provider, graph.providers, providerOverride = cfg.default_provider)
  infoCF("gateway", "Provider resolution", {"model": tech.model, "base": tech.apiBase}.toTable)
  let msgBus = newMessageBus()
  let provider = createProvider(tech.model, tech.apiKey, tech.apiBase)
  let cronStorePath = workspacePath(cfg[]) / "automation" / "jobs.json"
  var cronServiceInstance: CronService = nil
  cronServiceInstance = newCronService(cronStorePath)

  gChanManager = newManager(cfg[], msgBus)
  gChanManager.initChannels()
  
  gCtx = GatewayContext(
    cfg: cfg[],
    msgBus: msgBus,
    provider: provider,
    cronService: cronServiceInstance,
    offices: initTable[string, AgentLoop]()
  )

  cronServiceInstance.onJob = cronHandler
  
  if not gCtx.offices.hasKey("lexi"): gCtx.offices["lexi"] = newAgentLoop(gCtx.cfg, gCtx.msgBus, gCtx.provider, "Lexi", gCtx.cronService)
  let lexiWorkspace = cfg[].workspacePath() / "offices" / "lexi"
  let hbService = newHeartbeatService(lexiWorkspace, proc(p: string): Future[void] {.async.} =
    discard await gCtx.offices["lexi"].processDirect(p, "system:heartbeat")
  , 1800, true)

  echo "Gateway running on ", host, ":", port

  discard (proc() {.async.} =
    while true:
      try:
        let msg = await msgBus.consumeInbound()
        let recipient = if msg.recipient_id == "": "Lexi" else: msg.recipient_id
        let officeKey = recipient.toLowerAscii()
        
        if not gCtx.offices.hasKey(officeKey):
          infoCF("gateway", "Opening new office", {"agent": recipient}.toTable)
          gCtx.offices[officeKey] = newAgentLoop(gCtx.cfg, gCtx.msgBus, gCtx.provider, recipient, gCtx.cronService)
          
        # Extract plain text from JSON content (e.g. Feishu sends {"text":"/model"})
        var plainContent = msg.content.strip()
        if plainContent.startsWith("{"):
          try:
            let j = parseJson(plainContent)
            if j.hasKey("text"):
              plainContent = j["text"].getStr().strip()
          except: discard

        var response = ""
        if plainContent.startsWith("/"):
          var sysMsg = msg
          sysMsg.content = plainContent
          infoCF("gateway", "Processing system command", {"cmd": plainContent}.toTable)
          response = await handleSystemCommand(cfg, sysMsg, gCtx.offices[officeKey])
        else:
          response = await gCtx.offices[officeKey].processMessage(msg)
          
        if response != "":
          msgBus.publishOutbound(newOutbound(msg.channel, recipient, msg.chat_id, response))
      except Exception as e:
        errorCF("gateway", "Message loop error", {"error": e.msg}.toTable)
        await sleepAsync(1000)
  )()

  asyncCheck hbService.start()
  asyncCheck cronServiceInstance.start()
  waitFor gChanManager.startAll()

  # Ignore SIGHUP so gateway survives parent shell exit
  signal(SIGHUP, SIG_IGN)

  # Register signal handlers for clean exit
  setControlCHook(proc() {.noconv.} =
    gracefulShutdown()
    quit(0)
  )

  echo logo, " Gateway started. Press Ctrl+C to stop."
  while true: 
    try:
      poll()
    except Exception as e:
      if e.msg.contains("Interrupted system call"): break
      errorCF("gateway", "Poll exception", {"error": e.msg}.toTable)
  
  gracefulShutdown()

proc service*(args: seq[string]) =
  ## Manage nimclaw services — lifecycle, providers, channels, agents, skills
  let (action, msg) = runServiceCli(args)
  if msg != "": echo msg
  case action
  of saGatewayRun: gateway(@["run"])
  of saGatewayKill: gateway(@["kill"])
  of saOutput: discard

when isMainModule:
  loadDotEnv()
  dispatchMulti(
    ["multi", doc = "nimclaw — AI agent framework"],
    [service, positional = "args"],
    [version],
    [doctor_cmd, cmdName = "doctor"]
  )
