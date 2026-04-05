# NimClaw

Ultra-lightweight AI agent framework written in Nim. A high-performance clone of [PicoClaw](https://github.com/picoclaw).

## Why NimClaw?

- **Tiny footprint** — under 10MB RAM, single static binary
- **Multi-channel** — Telegram, Discord, QQ, Feishu/Lark, DingTalk, WhatsApp, MaixCam, nMobile
- **Any LLM** — OpenAI-compatible APIs: DeepSeek, Groq, OpenRouter, Anthropic, and more
- **Rich toolset** — filesystem, shell, web, cron, git, MCP integration, hardware (i2c, spi)
- **Extensible** — loadable skills via SKILL.md files and OpenClaw plugins
- **World graph** — entity/relationship model with RBAC for multi-agent coordination
- **Zero heavy deps** — no Node.js, no Python, no Docker required at runtime

## Quick Start

Download a prebuilt release or [build from source](GUIDE.md#build-from-source), then:

```bash
./nimclaw onboard
./nimclaw gateway
```

See the [Setup Guide](GUIDE.md) for full instructions.

## Architecture

```
Channel → MessageBus → Gateway → AgentLoop → LLM Provider → MessageBus → Channel
```

Channels listen for messages, the gateway routes them to agent loops, agents call LLM providers with tool access, and responses flow back through the bus to the originating channel.

## License

[MIT](LICENSE)
