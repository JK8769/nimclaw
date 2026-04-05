---
name: nimclaw-text-gen-image
description: "Use when user needs to generate images from text descriptions. Routes to AnyGen's ai_designer operation. Requires anygen skill."
metadata:
  requires_skills:
    - anygen
---

# Image Generation

Generate images from text descriptions using AnyGen's `ai_designer` operation.

## Quick Reference

This skill routes to the anygen `ai_designer` operation. Load the full workflow from `operations/image.md` in the anygen skill directory.

## Workflow Summary

### Step 1: Prepare the request

```bash
python3 {anygen_skill_dir}/scripts/anygen.py prepare \
  --message "A cute orange cat napping in sunlight, warm tones, soft lighting" \
  --save ./conversation.json
```

If the user provides a reference image, upload it first:

```bash
python3 {anygen_skill_dir}/scripts/anygen.py upload --file ./reference.png
# Output: File Token: tk_abc123

python3 {anygen_skill_dir}/scripts/anygen.py prepare \
  --message "Generate a poster in this style" \
  --file-token tk_abc123 \
  --save ./conversation.json
```

### Step 2: Confirm with user, then create

```bash
python3 {anygen_skill_dir}/scripts/anygen.py create \
  --operation ai_designer \
  --prompt "<prompt from suggested_task_params>"
# Output: Task ID: task_xxx, Task URL: https://...
```

### Step 3: Monitor and deliver

Poll for completion, then share the result URL with the user.

## Tips

- Detailed prompts produce better results: describe subject + scene + style + color tone
- Generation takes about 5-10 minutes — notify the user and monitor in background
- Use `sessions_spawn` for background monitoring if available
- For diagrams/flowcharts, use the `smart_draw` operation instead

## Prerequisites

- AnyGen skill must be installed (`nimclaw skills install anygen`)
- `ANYGEN_API_KEY` must be configured
