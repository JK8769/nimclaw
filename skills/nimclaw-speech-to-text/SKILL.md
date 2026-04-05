---
name: nimclaw-speech-to-text
description: "Use when user needs to convert audio or voice recordings to text. Uses Groq Whisper API (built-in) or Ollama whisper model."
---

# Speech to Text

Convert audio files to text using available transcription services.

## Method 1: Groq Whisper (Built-in)

NimClaw has built-in support for Groq's Whisper API. If a Groq provider is configured with an API key, voice messages received through channels are transcribed automatically.

For manual transcription via shell:

```bash
curl -s https://api.groq.com/openai/v1/audio/transcriptions \
  -H "Authorization: Bearer $GROQ_API_KEY" \
  -F "model=whisper-large-v3" \
  -F "file=@recording.mp3" \
  -F "language=zh"
```

## Method 2: Ollama Whisper (Local)

For fully local transcription without API keys:

```bash
# Install Ollama (macOS)
brew install ollama

# Use a speech model
ollama run whisper "Transcribe this audio" --audio ./meeting.mp3
```

Note: Ollama audio support depends on model availability. Check `ollama list` for models with audio capability.

## Method 3: OpenAI-compatible Whisper API

Any OpenAI-compatible provider with a Whisper endpoint:

```bash
curl -s $API_BASE/audio/transcriptions \
  -H "Authorization: Bearer $API_KEY" \
  -F "model=whisper-large-v3" \
  -F "file=@recording.mp3" \
  -F "language=en"
```

## Supported Languages

| Code | Language | Code | Language |
|------|----------|------|----------|
| `zh` | Chinese | `fr` | French |
| `en` | English | `es` | Spanish |
| `ja` | Japanese | `pt` | Portuguese |
| `ko` | Korean | `id` | Indonesian |
| `ru` | Russian | `ms` | Malay |

## Common Mistakes

| Mistake | Correct |
|---------|---------|
| Audio file too long (>10 min) | Split into shorter segments first |
| Wrong language code | Verify audio language matches the `language` parameter |
| Mixed-language audio with single code | Use the dominant language, or split by language segments |
| No API key configured | Set up a Groq provider or use local Ollama |
