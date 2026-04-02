# 🦞 NimClaw Getting Started Guide

Welcome to **NimClaw**, your ultra-lightweight personal AI agent! This guide will help you set up your environment and start collaborating with your new AI partner.

## 1. Initial Setup
If you haven't already, start by regularizing your environment.
```bash
./nimclaw onboard
```
This will set up your `.nimclaw` directory, initialize the world graph, and prepare default agents.

## 2. Configure Your AI Provider
NimClaw needs a brain! Link your preferred LLM provider:
```bash
./nimclaw provider add anthropic --api-key YOUR_KEY
```
*(You can also use `openai`, `deepseek`, or `groq`)*

## 3. Meet Lexi
Lexi is your default collaborator. Start a conversation directly from your terminal:
```bash
./nimclaw agent "Hello Lexi, can you help me organize my tasks?"
```

## 4. Explore Competencies (Skills)
Enhance NimClaw with platform-level skills:
- **Native Skills**: Place `SKILL.md` files in `.nimclaw/skills/`
- **OpenClaw Plugins**: Place `openclaw.plugin.json` plugins in `.nimclaw/plugins/`
- **Manage via CLI**:
  ```bash
  ./nimclaw competencies list
  ./nimclaw competencies search
  ```

## 5. Useful Commands
- `nimclaw status`: Check the health of your providers and channels.
- `nimclaw doctor`: Run system diagnostics.
- `nimclaw snapshot`: Create a restore point for your configuration.

---
*For deep technical details, check the `docs/` folder or visit the project repository.*
