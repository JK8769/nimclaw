import std/[os, strutils, unicode]
import unicodedb/[widths, properties]

proc splitTableRow(row: string): seq[string] =
  var s = row.strip()
  if s.startsWith("|"): s = s[1 .. ^1]
  if s.endsWith("|"): s = s[0 .. ^2]
  for part in s.split("|"):
    result.add(part.strip())

proc isTableSeparatorRow(row: string): bool =
  let cells = splitTableRow(row)
  if cells.len == 0: return false
  for c in cells:
    if c.len == 0: return false
    for ch in c:
      if ch notin {'-', ':', ' '}:
        return false
  true

proc displayWidth(s: string): int =
  for r in s.runes:
    if combining(r) != 0:
      continue
    case unicodeWidth(r)
    of uwdtWide, uwdtFull:
      result += 2
    else:
      result += 1

proc formatTableBlock(lines: seq[string]): seq[string] =
  if lines.len < 2: return lines
  if not isTableSeparatorRow(lines[1]): return lines
  var rows: seq[seq[string]] = @[]
  for l in lines:
    rows.add(splitTableRow(l))
  var cols = 0
  for r in rows:
    if r.len > cols: cols = r.len
  if cols == 0: return lines
  for i in 0 ..< rows.len:
    while rows[i].len < cols:
      rows[i].add("")
  var firstWidth = 3
  for r in rows:
    if r.len > 0:
      let w = displayWidth(r[0])
      if w > firstWidth:
        firstWidth = w

  proc fmtCell0(s: string): string =
    let pad = max(firstWidth - displayWidth(s), 0)
    s & repeat(' ', pad)

  proc fmtRow(r: seq[string]): string =
    var parts: seq[string] = @[]
    if r.len > 0:
      parts.add(fmtCell0(r[0]))
    for i in 1 ..< r.len:
      parts.add(r[i])
    "| " & parts.join(" | ") & " |"

  proc sepRow(): string =
    var parts: seq[string] = @[]
    parts.add(repeat('-', firstWidth))
    for i in 1 ..< cols:
      parts.add("---")
    "| " & parts.join(" | ") & " |"

  result.add(fmtRow(rows[0]))
  result.add(sepRow())
  for i in 2 ..< rows.len:
    result.add(fmtRow(rows[i]))

when isMainModule:
  let input = """
|              | **V5 工具**    | **UAT V1 工具**              | 
| ------------ | -------------- | ---------------------------- | 
| **核心区别** | 纯文本，直接写 | Markdown，格式全             | 
| **输入**     | `标题\n正文`   | `# 标题\n**正文**`           | 
| **输出效果** | 纯文本，无格式 | 正式文档，带排版             | 
| **配置**     | 无需额外配置   | 需 `app_id` + `user_open_id` | 
| **适合**     | 快速记录、草稿 | 周报、技术文档、正式报告     | 
"""

  var lines: seq[string] = @[]
  for l in input.splitLines():
    let s = l.strip()
    if s.len > 0:
      lines.add(s)
  let outLines = formatTableBlock(lines)
  let outText = "```\n" & outLines.join("\n") & "\n```"
  let outPath = getCurrentDir() / ".nimclaw" / "table_align_check.txt"
  writeFile(outPath, outText)
  echo outText
