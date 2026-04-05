# NimClaw Setup Guide

## Install

### Prebuilt binaries

Download the latest release for your platform from [Releases](../../releases). Each release includes `nimclaw`, `nkn_bridge`, and `lark-cli`.

### Build from source

Requires Nim 2.0+, Go 1.21+, libcurl, and OpenSSL.

```bash
git clone --recurse-submodules https://github.com/JK8769/nimclaw
cd nimclaw

nimble install -y
nimble build_all    # builds nimclaw + NKN bridge + lark-cli
```

To build components individually:

```bash
nimble build         # NimClaw only
nimble build_nkn     # NKN bridge (Go 1.21+)
nimble build_lark    # Feishu/Lark CLI (Go 1.23+, Python 3)
```

Cross-compile Go bridges:

```bash
./thridparty/build_libnkn.sh linux amd64
./thridparty/build_lark_cli.sh linux amd64
```

## First-time setup

```bash
./nimclaw onboard
```

This creates your `~/.nimclaw/` directory, sets up the world graph, configures an LLM provider, and prepares the default agent (Lexi).

Override the config directory with:

```bash
export NIMCLAW_DIR=/path/to/config
```

## Add a channel

### Feishu / Lark

1. Create an app at https://open.feishu.cn/app
2. Enable the **Event Subscription** capability and add `im.message.receive_v1`
3. Run:

```bash
./nimclaw channel add feishu <APP_ID> <APP_SECRET>
```

The secret is stored securely by lark-cli (macOS Keychain / Linux secret-service). Only the App ID is saved in your config.

### Telegram

Edit `~/.nimclaw/BASE.json` and set your bot token:

```json
"telegram": {
  "enabled": true,
  "token": "123456:ABC-DEF..."
}
```

### Other channels

Discord, QQ, DingTalk, WhatsApp, MaixCam, and nMobile are configured in the `channels` section of `BASE.json`. See [CLAUDE.md](CLAUDE.md) for the full config reference.

## Talk to your agent

From the terminal:

```bash
./nimclaw agent "Hello Lexi"
```

Or start the gateway to receive messages from connected channels:

```bash
./nimclaw gateway
```

## Add skills

Place `SKILL.md` files in `~/.nimclaw/skills/` or OpenClaw plugins in `~/.nimclaw/plugins/`.

```bash
./nimclaw skills list
./nimclaw skills search
```

## Useful commands

| Command | Description |
|---------|-------------|
| `nimclaw status` | Check provider and channel health |
| `nimclaw doctor` | Run system diagnostics |
| `nimclaw models list` | List available models |
| `nimclaw channel status` | Show channel status |
| `nimclaw agents list` | List configured agents |

## Development mode

For local development, use `nimble dev` which sets `NIMCLAW_DIR` to `.nimclaw/` in the project root:

```bash
nimble dev onboard
nimble dev gateway
nimble dev agent "hello"
```
