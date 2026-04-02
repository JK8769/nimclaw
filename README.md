# NimClaw

Ultra-lightweight AI agent framework written in Nim. A high-performance clone of [PicoClaw](https://github.com/picoclaw).

## Features

- Multi-channel support: Telegram, Discord, QQ, Feishu, DingTalk, WhatsApp, MaixCam, nMobile
- Configurable LLM backends via OpenAI-compatible APIs (DeepSeek, Groq, OpenRouter, Anthropic, etc.)
- Rich toolset: filesystem, shell, web, cron, git, MCP integration, hardware (i2c, spi)
- Loadable skills via SKILL.md files and OpenClaw plugins
- World graph (Cortex) with entities, relationships, and RBAC
- <10MB RAM footprint
- Zero heavy dependencies for channels

## Requirements

- Nim 2.0+
- libcurl (for HTTP)
- OpenSSL (for TLS)
- Go 1.21+ (for building NKN bridge and lark-cli)
- Python 3 (for lark-cli metadata fetching)

## Build

### From source (developers)

```bash
# Clone with submodules
git clone --recurse-submodules https://github.com/pico-claw/nimclaw
cd nimclaw

# Install Nim dependencies
nimble install -y

# Build everything (NimClaw + NKN bridge + lark-cli)
nimble build_all

# Or build individually
nimble build_nkn     # NKN/nMobile bridge (Go 1.21+)
nimble build_lark    # Feishu/Lark CLI (Go 1.23+, Python 3)
nimble build         # NimClaw only
```

Cross-compile Go bridges for another platform:

```bash
./thridparty/build_libnkn.sh linux amd64
./thridparty/build_lark_cli.sh linux amd64
```

### Prebuilt binaries (users)

Download the latest release for your platform from [Releases](../../releases). Each release includes `nimclaw`, `nkn_bridge`, and `lark-cli` — no Go or Python required.

## Quick Start

```bash
# First-time setup (local dev mode)
nimble dev onboard

# Start the gateway
nimble dev gateway

# Send a test message
nimble dev agent "hello"
```

### Production

```bash
./nimclaw onboard
./nimclaw gateway
```

## Configuration

NimClaw stores configuration and state in `~/.nimclaw/`. Override with the `NIMCLAW_DIR` environment variable:

```bash
export NIMCLAW_DIR=/path/to/config
./nimclaw onboard
```

For local development, `nimble dev` uses `.nimclaw/` in the project root.

## Architecture

```
Channel → MessageBus (inbound) → Gateway → AgentLoop → LLMProvider → MessageBus (outbound) → Channel
```

See [CLAUDE.md](CLAUDE.md) for detailed architecture documentation.

## License

[MIT](LICENSE)
