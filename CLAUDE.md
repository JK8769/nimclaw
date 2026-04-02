# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is NimClaw

NimClaw is a high-performance, ultra-lightweight AI agent framework written in Nim. It is a clone of PicoClaw. It connects to multiple chat channels (Telegram, Discord, QQ, Feishu, DingTalk, WhatsApp, MaixCam, nMobile) and routes messages through AI agents backed by configurable LLM providers. The default agent is named "Lexi".

## Build & Run

```bash
# Clone with submodules
git clone --recurse-submodules <repo-url>

# Install Nim dependencies
nimble install -y

# Build Go bridges (requires Go 1.21+)
./tools/build_libnkn.sh       # NKN/nMobile bridge subprocess
./tools/build_lark_cli.sh     # Feishu/Lark CLI (requires Python 3)

# Build NimClaw (ssl + release + threads are default switches)
nimble build

# Run in local dev mode (uses .nimclaw/ in project root)
nimble dev onboard          # first-time setup
nimble dev gateway          # start the gateway
nimble dev agent "hello"    # send a message to an agent

# Run tests
nimble test

# Generate docs
nimble docs
```

Requires Nim 2.0+, Go 1.21+. Build flags `--define:ssl --define:release --threads:on` are set in `nimclaw.nimble` and `config.nims`. Third-party dependencies (larksuite/cli, nMobile) are tracked as git submodules in `thridparty/`.

## Architecture

### Message Flow

`Channel -> MessageBus (inbound) -> Gateway -> AgentLoop -> LLMProvider -> MessageBus (outbound) -> Channel`

1. **Channels** (`src/nimclaw/channels/`) — Each channel (telegram, discord, etc.) polls or listens for messages and publishes `InboundMessage` to the `MessageBus`. The `Manager` initializes and starts all enabled channels.
2. **MessageBus** (`src/nimclaw/bus.nim`) — Thread-safe async queue with inbound/outbound deques, using locks for concurrency.
3. **Gateway** (`src/nimclaw.nim:gateway`) — The main long-running process. Consumes inbound messages, routes to the correct `AgentLoop` (one per agent name), and publishes outbound responses.
4. **AgentLoop** (`src/nimclaw/agent/loop.nim`) — Core agent logic. Manages the LLM conversation loop with tool calling iterations. Each agent has its own office directory and session state.
5. **Cortex** (`src/nimclaw/agent/cortex.nim`) — World graph with entities (Person, AI, Corporate), relationships, and RBAC roles. Agents resolve their identity and permissions through this graph.
6. **LLM Providers** (`src/nimclaw/providers/`) — HTTP-based provider using `curly`. Supports OpenAI-compatible APIs (DeepSeek, Groq, OpenRouter, Anthropic, etc.) via configurable `apiBase`.
7. **Tools** (`src/nimclaw/tools/`) — Large set of tools registered in a `ToolRegistry`. Tools are exposed to the LLM as callable functions. Includes filesystem, shell, web, cron, git, memory, MCP integration, hardware (i2c, spi), and more.
8. **Skills** (`src/nimclaw/skills/`) — Loadable SKILL.md files and OpenClaw plugins that extend agent capabilities. Loaded from workspace, project, private, global, and builtin directories.
9. **Services** (`src/nimclaw/services/`) — Background services: `CronService` for scheduled jobs, `HeartbeatService` for periodic agent prompts.
10. **Sessions** (`src/nimclaw/session.nim`) — Persists conversation history per session key as JSON files.

### Configuration

- Config lives in `~/.nimclaw/` (override with `NIMCLAW_DIR` env var). `nimble dev` uses `.nimclaw/` in project root.
- Config types defined in `src/nimclaw/config.nim`. Serialized with `jsony`.
- `.env` files are loaded from both CWD and the nimclaw dir.

### Key Dependencies

- `jsony` — JSON serialization
- `cligen` — CLI subcommand dispatch
- `curly` — HTTP client (wraps libcurl)
- `ws` — WebSocket client
- `nimcrypto` — Cryptographic operations
- `nimsync` — Synchronization primitives

### MCP Integration

The `ToolRegistry` can connect to external MCP (Model Context Protocol) servers via stdio, registering their tools dynamically alongside built-in tools.
