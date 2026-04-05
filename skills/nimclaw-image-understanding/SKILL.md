---
name: nimclaw-image-understanding
description: "Use when user sends an image or asks to analyze/describe image content. Uses the image_analyze tool."
---

# Image Understanding

Analyze and describe images using the `image_analyze` tool.

## Usage

When you see `[image: /path/to/file.jpg]` in a message, use the `image_analyze` tool:

```
image_analyze(path="/path/to/file.jpg", prompt="Describe this image in detail")
```

The tool automatically finds a vision-capable model from the configured providers, encodes the image, and returns the analysis. If no vision model is available, it returns a clear error message.

## Example Prompts

| Task | Prompt |
|------|--------|
| General description | "Describe this image in detail" |
| OCR / text extraction | "Extract all visible text from this image" |
| Object identification | "What objects are in this image?" |
| Color/style analysis | "Analyze the color palette and composition" |
| Specific question | "How many people are in this photo?" |

## Related Tools

| Tool | Purpose |
|------|---------|
| `image_analyze` | Analyze image content with a vision model |
| `image_info` | Get image metadata (format, dimensions, size) — no vision needed |
| `screenshot` | Capture the screen, then analyze with `image_analyze` |

## Decision Tree

```
User sends/references an image
├─ Need to understand content → image_analyze(path, prompt)
├─ Need metadata only (dimensions, format) → image_info(path)
├─ Need to capture screen first → screenshot(), then image_analyze()
├─ Image is in a document (PDF/PPT) → use nimclaw-doc-parse skill
└─ Need to generate images → use nimclaw-text-gen-image skill
```
