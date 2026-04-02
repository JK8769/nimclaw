import std/[os, strutils, options, json]
import jsony

type
  AgentDefaultsConfig* = object
    workspace*: string
    model*: string
    max_tokens*: int
    temperature*: float64
    max_tool_iterations*: int
    stream_intermediary*: bool

  NamedAgentConfig* = object
    name*: string
    nkn_identifier*: Option[string]
    api_key*: Option[string]
    provider*: string
    model*: string
    max_depth*: int
    system_prompt*: Option[string]
    temperature*: Option[float64]
    role*: Option[string]
    entity*: string # "AI", "Human", "Corporate"
    identity*: string # "User", "Staff", "Agent", "Customer", "Guest"

  AgentsSecurityConfig* = object
    allowed_paths*: seq[string]

  AgentsConfig* = object
    defaults*: AgentDefaultsConfig
    security*: AgentsSecurityConfig
    named*: seq[NamedAgentConfig]

  WhatsAppConfig* = object
    enabled*: bool
    bridge_url*: string
    allow_from*: seq[string]

  TelegramConfig* = object
    enabled*: bool
    token*: string
    allow_from*: seq[string]
    notification_only*: bool

  FeishuAppConfig* = object
    enabled*: Option[bool]
    app_id*: string
    app_secret*: string
    encrypt_key*: string
    verification_token*: string

  FeishuConfig* = object
    enabled*: bool
    stream_intermediary*: bool
    apps*: seq[FeishuAppConfig]
    allow_from*: seq[string]
    require_mention*: bool

  DiscordConfig* = object
    enabled*: bool
    token*: string
    allow_from*: seq[string]

  MaixCamConfig* = object
    enabled*: bool
    host*: string
    port*: int
    allow_from*: seq[string]

  QQConfig* = object
    enabled*: bool
    app_id*: string
    app_secret*: string
    allow_from*: seq[string]

  DingTalkConfig* = object
    enabled*: bool
    client_id*: string
    client_secret*: string
    allow_from*: seq[string]

  NMobileConfig* = object
    enabled*: bool
    stream_intermediary*: bool
    wallet_json*: string
    password*: string
    identifier*: string
    allow_from*: seq[string]
    fcm_key*: string
    push_proxy*: string
    decrypt_ipfs_cache*: Option[bool]
    enable_offline_queue*: bool
    message_ttl_hours*: int
    num_sub_clients*: int
    original_client*: bool
    telegram_push_chat_id*: Option[string]

  ChannelsConfig* = object
    whatsapp*: WhatsAppConfig
    telegram*: TelegramConfig
    feishu*: FeishuConfig
    discord*: DiscordConfig
    maixcam*: MaixCamConfig
    qq*: QQConfig
    dingtalk*: DingTalkConfig
    nmobile*: NMobileConfig


  GatewayConfig* = object
    host*: string
    port*: int

  WebSearchConfig* = object
    api_key*: string
    max_results*: int
    provider*: string
    fallback_providers*: seq[string]

  WebToolsConfig* = object
    search*: WebSearchConfig

  ToolsConfig* = object
    web*: WebToolsConfig

  PeripheralsConfig* = object
    boards*: seq[string]
    datasheet_dir*: string

  Config* = object
    default_provider*: string
    default_model*: string
    default_temperature*: float64
    agents*: AgentsConfig
    channels*: ChannelsConfig
    peripherals*: PeripheralsConfig
    gateway*: GatewayConfig
    tools*: ToolsConfig

proc expandHome*(path: string): string =
  if path == "": return path
  if path[0] == '~':
    let home = getHomeDir()
    if path.len > 1 and path[1] == '/':
      return home / path[2..^1]
    return home
  return path

var cachedNimClawDir {.threadvar.}: string

proc getNimClawDir*(): string =
  ## Returns the base directory for NimClaw. Result is cached after first call.
  ## Priority: NIMCLAW_DIR env var > local ./.nimclaw > ~/.nimclaw
  if cachedNimClawDir != "": return cachedNimClawDir

  let envDir = getEnv("NIMCLAW_DIR")
  if envDir != "":
    cachedNimClawDir = envDir
  elif dirExists("./.nimclaw"):
    cachedNimClawDir = getCurrentDir() / ".nimclaw"
  else:
    cachedNimClawDir = expandHome("~/.nimclaw")
  return cachedNimClawDir
  
proc getOpenClawDir*(): string =
  ## Returns the base directory for OpenClaw.
  ## Priority: 
  ## 1. OPENCLAW_DIR environment variable
  ## 2. ~/.openclaw
  let envDir = getEnv("OPENCLAW_DIR")
  if envDir != "": return envDir
  return expandHome("~/.openclaw")

proc getTemplateDir*(): string =
  ## Finds the best source for templates
  # 1. Local project dir (highest priority for development)
  let local = getCurrentDir() / "templates"
  if dirExists(local): return local
  
  # 2. Compile-time source root (robust for Nimble installations)
  const srcRoot = currentSourcePath().parentDir() / ".." # back from src/nimclaw/
  const bundle = srcRoot / "templates"
  if dirExists(bundle): return bundle
  
  # 3. Last resort fallback
  return getNimClawDir() / "templates"

proc defaultConfig*(): Config =
  result = Config(
    default_provider: "openrouter",
    default_temperature: 0.7,
    agents: AgentsConfig(
      defaults: AgentDefaultsConfig(
        workspace: getNimClawDir() / "workspace",
        model: "openrouter",
        max_tokens: 4096,
        temperature: 0.7,
        max_tool_iterations: 20,
        stream_intermediary: true
      ),
      security: AgentsSecurityConfig(
        allowed_paths: @[]
      )
    ),
    channels: ChannelsConfig(
      whatsapp: WhatsAppConfig(enabled: false, bridge_url: "ws://localhost:3001"),
      telegram: TelegramConfig(enabled: false, notification_only: false),
      feishu: FeishuConfig(enabled: false, stream_intermediary: false),
      discord: DiscordConfig(enabled: false),
      maixcam: MaixCamConfig(enabled: false, host: "0.0.0.0", port: 18790),
      qq: QQConfig(enabled: false),
      dingtalk: DingTalkConfig(enabled: false),
      nmobile: NMobileConfig(
        enabled: false,
        stream_intermediary: false,
        enable_offline_queue: true,
        message_ttl_hours: 24,
        num_sub_clients: 4,
        original_client: false
      )
    ),
    gateway: GatewayConfig(host: "0.0.0.0", port: 18790),
    tools: ToolsConfig(
      web: WebToolsConfig(
        search: WebSearchConfig(
          max_results: 5,
          provider: "auto",
          fallback_providers: @["duckduckgo"]
        )
      )
    ),
    peripherals: PeripheralsConfig(
      boards: @[],
      datasheet_dir: ""
    )
  )

proc parseEnv*(cfg: var Config) =
  # Simple manual environment variable parsing to match Go's env library
  if existsEnv("NIMCLAW_AGENTS_DEFAULTS_WORKSPACE"): cfg.agents.defaults.workspace = getEnv("NIMCLAW_AGENTS_DEFAULTS_WORKSPACE")
  if existsEnv("NIMCLAW_AGENTS_DEFAULTS_MODEL"): cfg.agents.defaults.model = getEnv("NIMCLAW_AGENTS_DEFAULTS_MODEL")
  if existsEnv("NIMCLAW_AGENTS_DEFAULTS_STREAM_INTERMEDIARY"): cfg.agents.defaults.stream_intermediary = getEnv("NIMCLAW_AGENTS_DEFAULTS_STREAM_INTERMEDIARY") == "true"

  if existsEnv("NIMCLAW_MODEL"):
    let m = getEnv("NIMCLAW_MODEL")
    cfg.default_model = m
    cfg.agents.defaults.model = m
  if existsEnv("NIMCLAW_TEMPERATURE"):
    try:
      let temp = parseFloat(getEnv("NIMCLAW_TEMPERATURE"))
      if temp >= 0.0 and temp <= 2.0:
        cfg.default_temperature = temp
    except ValueError:
      discard # ignore invalid floats
  if existsEnv("NIMCLAW_AGENT_MAX_ITERATIONS"):
    try: cfg.agents.defaults.max_tool_iterations = parseInt(getEnv("NIMCLAW_AGENT_MAX_ITERATIONS"))
    except ValueError: discard
    
  if existsEnv("NIMCLAW_ALLOWED_PATHS"):
    let pathsRaw = getEnv("NIMCLAW_ALLOWED_PATHS")
    if pathsRaw.len > 0:
      cfg.agents.security.allowed_paths = pathsRaw.split(";")
      
  if existsEnv("NIMCLAW_GATEWAY_PORT"):
    try:
      cfg.gateway.port = parseInt(getEnv("NIMCLAW_GATEWAY_PORT"))
    except ValueError:
      discard
  if existsEnv("NIMCLAW_GATEWAY_HOST"): cfg.gateway.host = getEnv("NIMCLAW_GATEWAY_HOST")
  if existsEnv("NIMCLAW_WORKSPACE"): cfg.agents.defaults.workspace = getEnv("NIMCLAW_WORKSPACE")

  
  # NKN Secrets
  if existsEnv("NIMCLAW_NKN_PASSWORD"): cfg.channels.nmobile.password = getEnv("NIMCLAW_NKN_PASSWORD")

proc getConfigPath*(): string =
  getNimClawDir() / "config.json"

proc loadConfig*(path: string): Config =
  result = defaultConfig()
  
  # 1. Try unified BASE.json first (Atomic Preference)
  let unifiedPath = parentDir(path) / "BASE.json"
  if fileExists(unifiedPath):
    try:
      let root = parseFile(unifiedPath)
      if root.hasKey("config"):
        let configNode = root["config"]
        result = ($configNode).fromJson(Config)
        parseEnv(result)
        return result
    except:
      discard
  
  # 2. Fallback to legacy config.json
  if fileExists(path):
    try:
      let data = readFile(path)
      result = data.fromJson(Config)
    except:
      discard

  parseEnv(result)

proc saveConfig*(path: string, cfg: Config) =
  let dir = parentDir(path)
  if not dirExists(dir):
    createDir(dir)
  
  # Priority: Update BASE.json if it exists
  let unifiedPath = dir / "BASE.json"
  if fileExists(unifiedPath):
    try:
      var root = parseFile(unifiedPath)
      root["config"] = parseJson(cfg.toJson())
      writeFile(unifiedPath, root.pretty())
      return
    except:
      discard
      
  writeFile(path, cfg.toJson())

proc workspacePath*(cfg: Config): string =
  expandHome(cfg.agents.defaults.workspace)
