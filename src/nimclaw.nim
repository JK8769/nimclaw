import std/[os, strutils, asyncdispatch, tables, times, options, posix, exitprocs]
import cligen
import nimclaw/[config, logger, bus, bus_types, session, agent/loop, agent/cortex, providers/http, providers/types as providers_types, doctor, cli_memory, cli_admin, cli_onboard, cli_providers]
import nimclaw/tools/remember
import nimclaw/channels/[manager as channel_manager]
import nimclaw/services/[heartbeat, cron as cron_service]
import nimclaw/libnkn/nkn_bridge
import std/random
import nimclaw/version as version_mod

# --- .env loading ---
proc loadDotEnv() =
  let paths = [
    getCurrentDir() / ".env",
    getNimClawDir() / ".env"
  ]
  for envPath in paths:
    if fileExists(envPath):
      for line in readFile(envPath).splitLines():
        let pair = line.split("=", 1)
        if pair.len == 2:
          let key = pair[0].strip()
          let val = pair[1].strip()
          if key.len > 0: putEnv(key, val)

const logo = "🦞🦞🦞"

proc version*() =
  ## Print the nimclaw version
  echo "nimclaw ", version_mod.versionString()

proc getGatewayPidPath(): string =
  getNimClawDir() / "gateway.pid"

proc isProcessAlive(pid: int): bool =
  if pid <= 0: return false
  return kill(pid.Pid, 0) == 0

proc killGateway(): bool =
  let pidPath = getGatewayPidPath()
  if not fileExists(pidPath):
    echo "No gateway PID file found."
    return false
  
  try:
    let pidStr = readFile(pidPath).strip()
    let pid = pidStr.parseInt()
    if isProcessAlive(pid):
      echo "Killing gateway process ", pid, "..."
      discard kill(pid.Pid, SIGTERM)
      # Wait a bit for it to die
      for _ in 1..10:
        if not isProcessAlive(pid): break
        sleep(200)
    
    removeFile(pidPath)
    echo "Gateway stopped."
    return true
  except:
    echo "Error killing gateway: ", getCurrentExceptionMsg()
    return false

proc doctor_cmd*(color: bool = true) =
  ## Check system configuration and health status
  putEnv("NO_COLOR", if not color: "1" else: "")
  doctor.runDoctor(loadConfig(getConfigPath()), color)

proc memory*(args: seq[string]) =
  ## Interact with the memory backend (count, forget, get, list, search)
  let cfg = loadConfig(getConfigPath())
  let workspace = cfg.workspacePath()
  let memBackend = newMarkdownMemory(workspace)
  echo runMemoryCommand(memBackend, args)

proc workspace*(args: seq[string]) =
  ## Manage workspace bootstrap files (edit, reset-md)
  let cfg = loadConfig(getConfigPath())
  echo runWorkspaceCommand(cfg, args)

proc capabilities*(json: bool = false) =
  ## Show nimclaw capabilities
  let cfg = loadConfig(getConfigPath())
  echo runCapabilitiesCommand(cfg, json)

proc models*(args: seq[string]) =
  ## Manage models (list, info, benchmark, refresh)
  let cfg = loadConfig(getConfigPath())
  echo runModelsCommand(cfg, args)

proc auth*(args: seq[string]) =
  ## Manage authentication (login, status, logout)
  echo runAuthCommand(args)

proc channel*(args: seq[string]) =
  ## Manage channels (list, status, add, remove)
  let cfg = loadConfig(getConfigPath())
  echo runChannelCommand(cfg, args)

proc hardware*(args: seq[string]) =
  ## Manage hardware devices (scan, flash, monitor)
  echo runHardwareCommand(args)

proc migrate*(args: seq[string]) =
  ## Migrate from other tools (openclaw)
  let cfg = loadConfig(getConfigPath())
  echo runMigrateCommand(cfg, args)

proc service*(args: seq[string]) =
  ## Manage system service (install, start, stop, restart, status, uninstall)
  let cfg = loadConfig(getConfigPath())
  let action = if args.len > 0: args[0] else: "status"
  echo runServiceCommand(cfg, @[action])

proc update*(check: bool = false, yes: bool = false) =
  ## Check for and apply updates
  var args: seq[string] = @[]
  if check: args.add("--check")
  if yes: args.add("--yes")
  echo runUpdateCommand(args)

proc initNKN*(cfg: var Config): string =
  ## Initialize a new NKN wallet if none exists
  if cfg.channels.nmobile.wallet_json != "": return ""

  randomize()
  let randomPassword = "nimclaw-v1-" & $rand(1000..9999)
  var bridge: NknBridge
  try:
    bridge = newNknBridge()
  except IOError as e:
    return e.msg
  defer: bridge.stop()
  let (walletJson, err) = bridge.getWallet(randomPassword)
  if err != "":
    return "Failed to generate wallet: " & err

  cfg.channels.nmobile.wallet_json = walletJson
  cfg.channels.nmobile.password = randomPassword
  cfg.channels.nmobile.identifier = "nimclaw"
  cfg.channels.nmobile.enabled = true
  return ""



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

proc onboard*(interactive = true, api_key = "", provider = "", model = "", memory = "markdown", restore = "") =
  ## Initialize the nimclaw directory, world graph, and default configuration
  let result = runOnboardCommand(getNimClawDir(), interactive, api_key, provider)
  echo result

  if result != "Cancelled.":
    echo logo, " nimclaw is ready! Check GUIDE.md to get started."

proc agents*(args: seq[string], all = false, profile: string = "", role: string = "") =
  ## Manage agents (list, rename)
  var cfg = loadConfig(getConfigPath())
  var msgArgs = args
  if all: msgArgs.add("--all")
  if profile != "": msgArgs.add("--profile=" & profile)
  if role != "": msgArgs.add("--role=" & role)
  echo runAgentsCommand(cfg, msgArgs)

proc provider*(args: seq[string], api_key = "", api_base = "", model = "", all = false) =
  ## Manage LLM providers (list, add, remove, health)
  let cfg = loadConfig(getConfigPath())
  var msgArgs = args
  if all: msgArgs.add("--all")
  echo runProviderCommand(cfg, msgArgs, api_key, api_base, model)

proc agent*(message: seq[string], session = "cli:default", debug = false, provider = "", model = "", temperature = -1.0, stream = true, recipient = "Lexi", sender = "user", channel = "cli") =
  ## Send a message to an agent
  if debug: setLevel(DEBUG)
  let logo = "🦞"
  
  var cfg = loadConfig(getConfigPath())
  let graph = loadWorld(getNimClawDir())
  
  var targetAgentName = recipient
  # Start with agent-specific config from world graph
  var tech = (model: cfg.agents.defaults.model, apiKey: "", apiBase: "")
  if graph.nameIndex.hasKey(targetAgentName):
    let aid = graph.nameIndex[targetAgentName]
    tech = graph.resolveTechnicalConfig(aid)

  # CLI overrides clear agent-specific credentials so we fall through to provider resolution
  if provider != "": tech.apiKey = ""; tech.apiBase = ""
  if model != "":
    tech.model = model
    if model.contains("/"): tech.apiKey = ""; tech.apiBase = ""

  # Fall back to provider-level resolution if no credentials yet
  if tech.apiKey == "":
    let resolved = resolveProviderTech(tech.model, cfg.default_provider, graph.providers, providerOverride = provider)
    tech.apiKey = resolved.apiKey
    if tech.apiBase == "": tech.apiBase = resolved.apiBase

  let agentLoop = newAgentLoop(cfg, newMessageBus(), createProvider(tech.model, tech.apiKey, tech.apiBase), targetAgentName, model = tech.model)
  let input = message.join(" ")

  if input != "": echo logo, " ", waitFor agentLoop.processDirect(input, session, sender, channel)
  else:
    let resolvedModel = if graph.nameIndex.hasKey(targetAgentName): graph.entities[graph.nameIndex[targetAgentName]].model else: cfg.agents.defaults.model
    echo logo, " Interactive mode (", cfg.default_provider, ":", resolvedModel, ") for ", targetAgentName, "\n"
    while true:
      stdout.write logo & " " & targetAgentName & " < You: "; let input = stdin.readLine().strip()
      if input in ["exit", "quit"]: break
      if input == "": continue
      echo "\n", logo, " ", waitFor agentLoop.processDirect(input, session, sender, channel), "\n"

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
          echo "Use './nimclaw gateway kill' to stop it, or './nimclaw gateway new' to restart."
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

  infoCF("gateway", "Starting", {"host": host, "port": $port}.toTable)
  var cfg = new(Config)
  cfg[] = loadConfig(getConfigPath())
  cfg.agents.defaults.stream_intermediary = stream
  let graph = loadWorld(cfg[].workspacePath())
  
  let tech = resolveProviderTech(cfg.agents.defaults.model, cfg.default_provider, graph.providers)
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
          
        var response = ""
        if msg.content.startsWith("/"):
          infoCF("gateway", "Processing system command", {"cmd": msg.content}.toTable)
          response = await handleSystemCommand(cfg, msg, gCtx.offices[officeKey])
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

proc status*() =
  let configPath = getConfigPath()
  echo logo, " nimclaw Status"
  if fileExists(configPath):
    let cfg = loadConfig(configPath)
    let workspace = cfg.workspacePath()
    echo "  Config:    ", configPath, " ✓"
    echo "  Workspace: ", workspace, if dirExists(workspace): " ✓" else: " ✗"
    echo "  Provider:  ", cfg.default_provider
    echo "  Model:     ", cfg.agents.defaults.model

proc automation*(list = false, add = false, add_agent = false, once = false,
          once_agent = false, run_job = "", pause = "", resume = "",
          runs = "", update_job = "",
          remove = "", enable = "", disable = "",
          name = "", message = "", every = 0, at = 0.0, cron_expr = "",
          deliver = true, channel = "", to = "", model = "") =
  let cfg = loadConfig(getConfigPath())
  let cs = newCronService(cfg.workspacePath() / "automation" / "jobs.json", nil)
  if list:
    for j in cs.listJobs(true): echo "$1 ($2) - $3".format(j.name, j.id, j.schedule.kind)
  elif add or add_agent or once or once_agent:
    let schedule = if once or once_agent:
                     if at > 0: CronSchedule(kind: "once", atMs: some(int64(times.getTime().toUnix() * 1000 + int64(at * 1000))))
                     else: CronSchedule(kind: "once", atMs: some(times.getTime().toUnix() * 1000 + 5000))
                   else:
                     if cron_expr != "": CronSchedule(kind: "cron", expr: cron_expr)
                     else: CronSchedule(kind: "interval", everyMs: some(int64(every * 1000)))
    
    let payload = CronPayload(
      kind: if add_agent or once_agent: "agent_turn" else: "message",
      message: message,
      deliver: deliver,
      channel: channel,
      to: to,
      model: model
    )
    
    let job = waitFor cs.addJob(name, schedule, payload)
    echo "Added job: ", job.name, " (", job.id, ")"
  elif remove != "":
    discard cs.removeJob(remove)
    echo "Removed job: ", remove
  elif pause != "":
    discard cs.enableJob(pause, false)
    echo "Paused job: ", pause
  elif resume != "":
    discard cs.enableJob(resume, true)
    echo "Resumed job: ", resume

proc competencies*(args: seq[string]) =
  let cfg = loadConfig(getConfigPath())
  echo runCompetenciesCommand(cfg.workspacePath(), getNimClawDir(), args)

proc nmobile*(args: seq[string]) =
  if args.len == 0 or args[0] != "pair":
    echo "Usage: nimclaw nmobile pair"
    return
  discard loadConfig(getConfigPath())
  echo "WIP"

proc backup*(full = false, output = "") =
  echo runBackupCommand(full, output)

proc restore_env*(args: seq[string]) =
  if args.len == 0: return
  echo runRestoreCommand(args[0])

when isMainModule:
  loadDotEnv()
  dispatchMulti(
    ["multi", doc = "nimclaw administrative tool"],
    [onboard],
    [agent, positional = "message"],
    [gateway],
    [status], 
    [automation], 
    [competencies, cmdName = "skills"], 
    [competencies], 
    [version],
    [doctor_cmd, cmdName = "doctor"],
    [provider],
    [memory],
    [workspace],
    [capabilities],
    [models],
    [auth],
    [channel],
    [hardware],
    [migrate],
    [agents],
    [service],
    [update],
    [backup], 
    [restore_env, cmdName = "restore", positional = "args"],
    [nmobile]
  )
