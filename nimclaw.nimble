version       = "0.1.0"
author        = "PicoClaw contributors"
description   = "Ultra-lightweight personal AI agent in Nim"
license       = "MIT"
srcDir        = "src"
bin           = @["nimclaw"]

requires "nim >= 2.0.0"
requires "jsony"
requires "cligen"
requires "ws"
requires "regex"
requires "nimsync >= 1.0.0"
requires "QRgen"
requires "curly"
requires "webby"
requires "nimcrypto"
requires "unicodedb"

# Standard build switches
switch("define", "ssl")
switch("define", "release")
switch("threads", "on")

# ── Helpers ──────────────────────────────────────────────────────

const knownSubcmds = ["new", "run", "stop", "deploy", "remove", "list", "help",
                       "channels", "plugins", "providers", "agents", "skills"]

# Config subcmds take rest args, not a service name after them
const configSubcmds = ["channels", "plugins", "providers", "agents", "skills"]

proc isSubcmd(s: string): bool =
  for c in knownSubcmds:
    if s == c: return true
  return false

proc isConfigSubcmd(s: string): bool =
  for c in configSubcmds:
    if s == c: return true
  return false

proc parseServiceArgs(): tuple[name, subcmd, rest: string] =
  ## Parse: nimble service [Name] <subcmd> [rest...]
  ## If first arg is a known subcmd, no service name (use default).
  ## Otherwise first arg is service name, second is subcmd.
  ## Config subcmds (channels, plugins, etc.) take rest args, not a name.
  var args: seq[string] = @[]
  var collect = false
  for i in 1..paramCount():
    let p = paramStr(i)
    if collect:
      args.add(p)
    elif p == "service":
      collect = true

  if args.len == 0:
    return ("", "", "")

  var name = ""
  var subcmd = ""
  var restStart = 0

  if args[0].isSubcmd():
    subcmd = args[0]
    if subcmd.isConfigSubcmd():
      # nimble service plugins add playwright — everything after subcmd is rest
      restStart = 1
    elif args.len > 1 and not args[1].startsWith("-"):
      # nimble service run MyCompany — next arg is service name
      name = args[1]
      restStart = 2
    else:
      restStart = 1
  else:
    # nimble service MyCompany channels add feishu
    name = args[0]
    if args.len > 1:
      subcmd = args[1]
      restStart = 2
    else:
      subcmd = "list"
      restStart = 1

  var rest = ""
  for i in restStart..<args.len:
    if rest.len > 0: rest.add(" ")
    rest.add(args[i])

  return (name, subcmd, rest)

proc serviceDir(name: string): string =
  if name == "": getCurrentDir() & "/.nimclaw"
  else: getCurrentDir() & "/.nimclaw-" & name

proc runWithService(name, args: string) =
  exec "env NIMCLAW_DIR=" & serviceDir(name) & " ./nimclaw" & args

# ── Service ──────────────────────────────────────────────────────

task service, "nimble service <command> — build + delegate to nimclaw service":
  # Collect all args after "nimble service"
  var args: seq[string] = @[]
  var collect = false
  for i in 1..paramCount():
    let p = paramStr(i)
    if collect:
      args.add(p)
    elif p == "service":
      collect = true

  # For "new", also build channel CLIs if Go is available
  let isNew = args.len > 0 and args[0] == "new"

  echo "=== Building NimClaw ==="
  exec "nimble install -y"
  exec "nimble build"

  if isNew:
    let go = findExe("go")
    if go.len > 0:
      echo ""
      echo "=== Building channel CLIs ==="
      exec "git submodule update --init channels/lark-cli clients/nMobile 2>/dev/null || true"
      exec "mkdir -p channels/bin"
      exec "./channels/build_nkn_cli.sh 2>/dev/null || true"
      exec "./channels/build_lark_cli.sh 2>/dev/null || true"

  echo ""
  exec "./nimclaw service " & args.join(" ")

# ── Build helpers ────────────────────────────────────────────────

task build_nkn, "Build nkn-cli (requires Go 1.21+)":
  exec "./channels/build_nkn_cli.sh"

task build_lark, "Build lark-cli from submodule (requires Go 1.23+, Python 3)":
  exec "./channels/build_lark_cli.sh"

task build_all, "Build NimClaw and all channel CLIs":
  exec "./channels/build_nkn_cli.sh"
  exec "./channels/build_lark_cli.sh"
  exec "nimble build"

# ── Test ─────────────────────────────────────────────────────────

task test, "Run unit tests":
  exec "nim c -r --hints:off tests/test_schema.nim"
  exec "nim c -r --hints:off tests/test_path_security.nim"
  exec "nim c -r --hints:off tests/test_filesystem.nim"
  exec "nim c -r --hints:off tests/test_tool_registry.nim"

# ── Docs ─────────────────────────────────────────────────────────

task docs, "Generate searchable HTML documentation":
  exec "nim doc --project --outdir:docs --index:on --hints:off --warnings:off src/nimclaw.nim"
  echo "Documentation generated in docs/"
