---
name: nimclaw-web-search
description: "ALWAYS use this skill FIRST when you need to find, look up, or verify ANY information from the internet — do NOT guess URLs and fetch them directly. Uses NimClaw's built-in web_search tool."
override-tools:
  - web_search
---

# Web Search

Use the built-in `web_search` tool to search the internet by keyword.

## Quick Reference

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `query` | Search keywords (be specific) | Yes | - |
| `count` | Number of results (1-10) | No | 5 |

## Usage

Call the `web_search` tool directly:

```json
{"query": "React 19 new features", "count": 5}
```

Returns titles, URLs, and snippets from search results.

## Decision Tree

```
User wants internet information
├─ Has a specific URL → use web_fetch tool (see nimclaw-web-fetch skill)
├─ No specific URL, needs search → use web_search tool
└─ Search then deep dive → web_search to find URLs → web_fetch to extract details
```

## Common Mistakes

| Mistake | Correct |
|---------|---------|
| Guessing URLs and fetching directly | Search first, then fetch specific URLs from results |
| Overly broad keywords | Use specific, focused keywords for better results |
| Not following up on results | Use `web_fetch` on promising URLs for full content |
