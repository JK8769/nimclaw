import std/[os, strutils, posix, json]
import config, cli_admin, cli_providers, cli_onboard

type
  ServiceAction* = enum
    saOutput       ## Just print the message
    saGatewayRun   ## Caller should start gateway
    saGatewayKill  ## Caller should kill gateway

  ServiceResult* = tuple[action: ServiceAction, message: string]

const
  lifecycleCmds = ["new", "run", "stop", "restart", "status", "deploy", "remove", "list"]
  configCmds = ["onboard", "provider", "channel", "agent", "plugin", "skill"]

proc isLifecycleCmd(s: string): bool =
  for c in lifecycleCmds:
    if s == c: return true

proc isConfigCmd(s: string): bool =
  for c in configCmds:
    if s == c: return true

# ── Service dir resolution ───────────────────────────────────────

proc serviceDir(name: string): string =
  ## Returns the canonical service dir path (does not check existence)
  if name == "": expandHome("~/.nimclaw")
  else: expandHome("~/.nimclaw-" & name)

proc localServiceDir(name: string): string =
  if name == "": getCurrentDir() / ".nimclaw"
  else: getCurrentDir() / ".nimclaw-" & name

proc resolveServiceDir(name: string): string =
  ## Find existing service dir: deployed (~/) first, then local (./)
  let deployed = serviceDir(name)
  if dirExists(deployed): return deployed
  let local = localServiceDir(name)
  if dirExists(local): return local
  return ""

proc setServiceEnv(name: string): string =
  ## Resolve service dir, set NIMCLAW_DIR, load .env. Returns dir or "" on failure.
  let dir = resolveServiceDir(name)
  if dir == "": return ""
  putEnv("NIMCLAW_DIR", dir)
  resetNimClawDir()
  loadDotEnv()
  return dir

# ── PID management ───────────────────────────────────────────────

proc getGatewayPidPath*(): string =
  getNimClawDir() / "gateway.pid"

proc isProcessAlive*(pid: int): bool =
  if pid <= 0: return false
  return kill(pid.Pid, 0) == 0

proc killGateway*(): bool =
  let pidPath = getGatewayPidPath()
  if not fileExists(pidPath):
    echo "No gateway PID file found."
    return false
  try:
    let pidStr = readFile(pidPath).strip()
    let pid = pidStr.parseInt()
    if isProcessAlive(pid):
      echo "Stopping gateway (PID ", pid, ")..."
      discard kill(pid.Pid, SIGTERM)
      for _ in 1..10:
        if not isProcessAlive(pid): break
        sleep(200)
    removeFile(pidPath)
    echo "Gateway stopped."
    return true
  except:
    echo "Error: ", getCurrentExceptionMsg()
    return false

# ── Lifecycle commands ───────────────────────────────────────────

proc serviceNew(name: string): string =
  let dir = if name == "": localServiceDir("") else: localServiceDir(name)
  let label = if name == "": "(default)" else: name

  if dirExists(dir):
    return "Service already exists: " & dir

  echo "Creating service: ", label
  echo "  Directory: ", dir

  let tplDir = getTemplateDir()

  createDir(dir)
  createDir(dir / "workspace")
  createDir(dir / "logs")
  createDir(dir / "channels")
  createDir(dir / "plugins")
  createDir(dir / "skills")

  # Seed workspace from templates
  seedWorkspace(tplDir, dir / "workspace")

  echo ""
  echo "Service created: ", label
  echo ""
  echo "Next steps:"
  if name != "":
    echo "  nimclaw service ", name, " onboard    # guided setup"
    echo "  nimclaw service run ", name, "         # start gateway"
  else:
    echo "  nimclaw service onboard               # guided setup"
    echo "  nimclaw service run                    # start gateway"
  return ""

proc serviceRun(name: string): ServiceResult =
  let dir = setServiceEnv(name)
  if dir == "":
    let label = if name == "": "(default)" else: name
    return (saOutput, "Service '" & label & "' not found.\nRun: nimclaw service new " & name)
  echo "Starting gateway from: ", dir
  return (saGatewayRun, "")

proc serviceStop(name: string): ServiceResult =
  let dir = setServiceEnv(name)
  if dir == "":
    let label = if name == "": "(default)" else: name
    return (saOutput, "Service '" & label & "' not found.")
  discard killGateway()
  return (saOutput, "")

proc serviceRestart(name: string): ServiceResult =
  let dir = setServiceEnv(name)
  if dir == "":
    let label = if name == "": "(default)" else: name
    return (saOutput, "Service '" & label & "' not found.")
  discard killGateway()
  echo "Restarting..."
  return (saGatewayRun, "")

proc serviceStatus(name: string): string =
  let dir = resolveServiceDir(name)
  let label = if name == "": "(default)" else: name
  if dir == "":
    return "Service '" & label & "' not found."

  var status = "Service: " & label & "\n  Directory: " & dir
  let pidPath = dir / "gateway.pid"
  if fileExists(pidPath):
    try:
      let pid = readFile(pidPath).strip().parseInt()
      if isProcessAlive(pid):
        status &= "\n  Status: running (PID " & $pid & ")"
      else:
        status &= "\n  Status: stopped (stale PID file)"
    except:
      status &= "\n  Status: unknown"
  else:
    status &= "\n  Status: stopped"

  let configPath = dir / "BASE.json"
  if fileExists(configPath):
    try:
      let base = parseFile(configPath)
      let provider = base{"config", "default_provider"}.getStr("?")
      let model = base{"config", "agents", "defaults", "model"}.getStr("?")
      status &= "\n  Provider: " & provider
      status &= "\n  Model: " & model
    except: discard

  return status

proc serviceDeploy(name: string): string =
  let dir = resolveServiceDir(name)
  if dir == "":
    let label = if name == "": "(default)" else: name
    return "Service '" & label & "' not found.\nRun: nimclaw service new " & name
  putEnv("NIMCLAW_DIR", dir)
  resetNimClawDir()
  let cfg = loadConfig(getConfigPath())
  return runDaemonCommand(cfg, name, @["install"])

proc serviceRemove(name: string): string =
  let dir = resolveServiceDir(name)
  let label = if name == "": "(default)" else: name
  if dir == "":
    return "Service '" & label & "' not found."

  # Check if running
  let pidPath = dir / "gateway.pid"
  if fileExists(pidPath):
    try:
      let pid = readFile(pidPath).strip().parseInt()
      if isProcessAlive(pid):
        return "Service '" & label & "' is running (PID " & $pid & ").\nStop it first: nimclaw service stop " & name
    except: discard

  removeDir(dir)
  return "Removed service: " & label

proc scanServiceDirs(baseDir, location: string, services: var seq[tuple[name, dir, status: string]]) =
  if dirExists(baseDir / ".nimclaw"):
    var found = false
    for s in services:
      if s.name == "(default)": found = true
    if not found:
      services.add(("(default)", baseDir / ".nimclaw", location))
  for kind, path in walkDir(baseDir):
    if kind != pcDir: continue
    let dirName = path.lastPathPart()
    if dirName.startsWith(".nimclaw-"):
      let name = dirName[".nimclaw-".len..^1]
      var found = false
      for s in services:
        if s.name == name: found = true
      if not found:
        services.add((name, path, location))

proc serviceList(): string =
  var services: seq[tuple[name, dir, status: string]] = @[]
  scanServiceDirs(getCurrentDir(), "local", services)
  scanServiceDirs(expandHome("~"), "deployed", services)

  if services.len == 0:
    return "No services found.\nRun: nimclaw service new MyCompany"

  var output = "Services:\n"
  for s in services:
    let pidPath = s.dir / "gateway.pid"
    var running = false
    if fileExists(pidPath):
      try:
        let pid = readFile(pidPath).strip().parseInt()
        running = isProcessAlive(pid)
      except: discard
    let state = if running: "running" else: "stopped"
    output &= "  " & s.name & "  " & state & "  (" & s.status & ") " & s.dir & "\n"
  return output.strip()

# ── Per-service commands ─────────────────────────────────────────

proc serviceOnboard(name: string): string =
  let dir = setServiceEnv(name)
  let label = if name == "": "(default)" else: name
  if dir == "":
    return "Service '" & label & "' not found.\nRun: nimclaw service new " & name

  echo "Onboarding service: ", label
  echo "  Directory: ", dir
  echo ""

  # 1. Check deps
  echo "=== Checking dependencies ==="
  let curl = findExe("curl")
  if curl == "": echo "  curl: MISSING (required)" else: echo "  curl: ok"
  let git = findExe("git")
  if git == "": echo "  git: not found (optional)" else: echo "  git: ok"
  let node = findExe("node")
  if node == "": echo "  node: not found (optional, for playwright)" else: echo "  node: ok"
  let python = findExe("python3")
  if python == "": echo "  python3: not found (optional)" else: echo "  python3: ok"
  echo ""

  if curl == "":
    return "Error: curl is required. Install it and try again."

  # 2. Provider setup (reuse existing onboard which handles provider interactively)
  echo "=== Provider Setup ==="
  let onboardResult = runOnboardCommand(dir, interactive = true)
  if onboardResult.contains("Cancelled"):
    return onboardResult
  echo onboardResult
  echo ""

  # 3. Channel setup
  echo "=== Channel Setup ==="
  var cfg = loadConfig(getConfigPath())
  echo runChannelCommand(cfg, @["add"])
  echo ""

  # 4. Agent setup
  echo "=== Agent Setup ==="
  echo runAgentsCommand(cfg, @["add"])
  echo ""

  echo "=== Onboarding Complete ==="
  echo ""
  if name != "":
    echo "Start your service:"
    echo "  nimclaw service run ", name
  else:
    echo "Start your service:"
    echo "  nimclaw service run"
  return ""

# ── Main dispatcher ──────────────────────────────────────────────

proc showUsage(): string =
  return """Usage: nimclaw service <command>

Lifecycle:
  new [Name]              Create a new service
  run [Name]              Start the gateway
  stop [Name]             Stop the gateway
  restart [Name]          Restart the gateway
  status [Name]           Show service status
  deploy [Name]           Install as system daemon
  remove [Name]           Delete a service
  list                    Show all services

Per-service:
  [Name] onboard          Guided setup (provider, channel, agent)
  [Name] provider <cmd>   Manage providers (list, add, remove, health)
  [Name] channel <cmd>    Manage channels (list, add, remove)
  [Name] agent <cmd>      Manage agents (list, add, remove)
  [Name] plugin <cmd>     Manage plugins (list, add, remove)
  [Name] skill <cmd>      Manage skills (list, install, remove, show)

Examples:
  nimclaw service new MyCompany
  nimclaw service MyCompany onboard
  nimclaw service MyCompany provider add deepseek
  nimclaw service run MyCompany"""

proc runServiceCli*(args: seq[string]): ServiceResult =
  if args.len == 0:
    return (saOutput, showUsage())

  # Parse: lifecycle cmd or per-service cmd?
  if args[0].isLifecycleCmd():
    let cmd = args[0]
    let name = if args.len > 1 and not args[1].startsWith("-"): args[1] else: ""

    case cmd
    of "new":
      return (saOutput, serviceNew(name))
    of "run":
      return serviceRun(name)
    of "stop":
      return serviceStop(name)
    of "restart":
      return serviceRestart(name)
    of "status":
      return (saOutput, serviceStatus(name))
    of "deploy":
      return (saOutput, serviceDeploy(name))
    of "remove":
      return (saOutput, serviceRemove(name))
    of "list":
      return (saOutput, serviceList())
    else:
      return (saOutput, "Unknown command: " & cmd)

  elif args[0].isConfigCmd():
    # No name — use default service
    let cmd = args[0]
    let rest = if args.len > 1: args[1..^1] else: @[]
    let dir = setServiceEnv("")
    if dir == "":
      return (saOutput, "No default service found.\nRun: nimclaw service new")

    var cfg = loadConfig(getConfigPath())
    case cmd
    of "onboard":
      return (saOutput, serviceOnboard(""))
    of "provider":
      return (saOutput, runProviderCommand(cfg, rest))
    of "channel":
      return (saOutput, runChannelCommand(cfg, rest))
    of "agent":
      return (saOutput, runAgentsCommand(cfg, rest))
    of "plugin":
      return (saOutput, runCompetenciesCommand(cfg.workspacePath(), getNimClawDir(), rest))
    of "skill":
      return (saOutput, runCompetenciesCommand(cfg.workspacePath(), getNimClawDir(), rest))
    else:
      return (saOutput, "Unknown command: " & cmd)

  else:
    # First arg is the service name
    let name = args[0]
    if args.len < 2:
      return (saOutput, serviceStatus(name))

    let cmd = args[1]
    let rest = if args.len > 2: args[2..^1] else: @[]

    if not cmd.isConfigCmd():
      return (saOutput, "Unknown command: " & cmd & "\n" & showUsage())

    let dir = setServiceEnv(name)
    if dir == "":
      return (saOutput, "Service '" & name & "' not found.\nRun: nimclaw service new " & name)

    var cfg = loadConfig(getConfigPath())
    case cmd
    of "onboard":
      return (saOutput, serviceOnboard(name))
    of "provider":
      return (saOutput, runProviderCommand(cfg, rest))
    of "channel":
      return (saOutput, runChannelCommand(cfg, rest))
    of "agent":
      return (saOutput, runAgentsCommand(cfg, rest))
    of "plugin":
      return (saOutput, runCompetenciesCommand(cfg.workspacePath(), getNimClawDir(), rest))
    of "skill":
      return (saOutput, runCompetenciesCommand(cfg.workspacePath(), getNimClawDir(), rest))
    else:
      return (saOutput, "Unknown command: " & cmd)
