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

proc collectTaskArgs(taskName: string): string =
  var collect = false
  for i in 1..paramCount():
    let p = paramStr(i)
    if collect:
      if p == "help": result.add(" --help")
      else: result.add(" " & p)
    elif p == taskName:
      collect = true

proc runLocal(args: string) =
  exec "env NIMCLAW_DIR=" & getCurrentDir() & "/.nimclaw ./nimclaw" & args

task usage, "Show NimClaw binary help":
  runLocal(" --help")

task dev, "Run NimClaw in local development mode":
  runLocal(collectTaskArgs("dev"))

task prod, "Clean start NimClaw by removing the local .nimclaw directory":
  let dir = getCurrentDir() & "/.nimclaw"
  if dirExists(dir):
    echo "Removing old .nimclaw for a fresh start..."
    exec "rm -rf " & dir
  runLocal(collectTaskArgs("prod"))

task snapshot, "Snapshot the current development .nimclaw directory":
  let timestamp = staticExec("date +%H%m%d_%H%M%S")
  let dir = getCurrentDir() & "/.nimclaw"
  if dirExists(dir):
    let backupDir = getCurrentDir() & "/.nimclaw_bak_" & timestamp
    exec "cp -r " & dir & " " & backupDir
    echo "Snapshotted .nimclaw to " & backupDir
  else:
    echo "No local .nimclaw directory found to snapshot."

task build_nkn, "Build NKN bridge (requires Go 1.21+)":
  exec "./thridparty/build_libnkn.sh"

task build_lark, "Build lark-cli from submodule (requires Go 1.23+, Python 3)":
  exec "./thridparty/build_lark_cli.sh"

task build_all, "Build NimClaw and all Go bridges":
  exec "./thridparty/build_libnkn.sh"
  exec "./thridparty/build_lark_cli.sh"
  exec "nimble build"

task test, "Run unit tests":
  exec "nim c -r --hints:off tests/test_schema.nim"
  exec "nim c -r --hints:off tests/test_path_security.nim"
  exec "nim c -r --hints:off tests/test_filesystem.nim"

task docs, "Generate searchable HTML documentation":
  exec "nim doc --project --outdir:docs --index:on --hints:off --warnings:off src/nimclaw.nim"
  echo "✔ Documentation suite generated in docs/"
