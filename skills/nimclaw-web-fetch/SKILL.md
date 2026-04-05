---
name: nimclaw-web-fetch
description: "Use when user needs to crawl or fetch a specific URL to extract and summarize its content. Uses NimClaw's built-in web_fetch tool."
override-tools:
  - web_fetch
---

# Web Fetch

Use the built-in `web_fetch` tool to fetch a URL and extract readable content.

## Quick Reference

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `url` | The URL to fetch | Yes | - |
| `maxChars` | Maximum characters to extract | No | - |

## Usage

Call the `web_fetch` tool directly:

```json
{"url": "https://example.com/article"}
```

Returns extracted text content from the page (HTML tags stripped).

## Decision Tree

```
User wants internet information
├─ Has a specific URL → use web_fetch tool
├─ No specific URL, needs search → use web_search tool (see nimclaw-web-search skill)
└─ Search then deep dive → web_search to find URLs → web_fetch to extract details
```

## Common Mistakes

| Mistake | Correct |
|---------|---------|
| Fetching without a specific URL | Use `web_search` first to find the right URL |
| Fetching very large pages without maxChars | Set `maxChars` for large pages to avoid token overflow |
| Fetching pages that require JavaScript | Use the `playwright` tool for JS-rendered pages |
