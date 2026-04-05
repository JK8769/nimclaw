---
name: nimclaw-doc-parse
description: "Use when user needs to parse, extract, or read content from documents (PDF, Word, Excel, PPT, etc.). Uploads to AnyGen for intelligent document parsing. Requires anygen skill."
metadata:
  requires_skills:
    - anygen
---

# Document Parse

Upload documents to AnyGen for intelligent parsing and content extraction.

## Supported Formats

| Format | Extensions | Typical Use |
|--------|-----------|-------------|
| PDF | `.pdf` | Reports, papers, contracts |
| Word | `.doc`, `.docx` | Documents, proposals |
| PowerPoint | `.pptx` | Presentations |
| Excel | `.xlsx` | Spreadsheets |
| CSV | `.csv` | Structured data |
| Text | `.txt`, `.md` | Plain text |
| HTML | `.html` | Web pages |

## Workflow

### Step 1: Upload the document

```bash
python3 {anygen_skill_dir}/scripts/anygen.py upload --file ./document.pdf
# Output: File Token: tk_abc123
```

### Step 2: Use the appropriate AnyGen operation

Choose based on what the user needs:

| Need | AnyGen Operation | Guide |
|------|-----------------|-------|
| Extract and restructure into a new document | `doc` | `operations/doc.md` |
| Analyze data from CSV/Excel | `data_analysis` | `operations/data_analysis.md` |
| Create slides from document content | `slide` | `operations/slide.md` |
| Research based on document content | `deep_research` | `operations/deep_research.md` |

```bash
python3 {anygen_skill_dir}/scripts/anygen.py prepare \
  --message "Extract and summarize the key findings from this report" \
  --file-token tk_abc123 \
  --save ./conversation.json
```

Then follow the AnyGen operation workflow (prepare → confirm → create → poll).

### For simple text extraction

If the user just needs raw text from a document, use the `shell` tool with common CLI utilities:

```bash
# PDF to text (requires pdftotext)
pdftotext document.pdf -

# Word/DOCX (requires pandoc)
pandoc document.docx -t plain

# Excel/CSV
cat data.csv
```

## Decision Tree

```
Need document content
├─ Simple text extraction → shell tool with pdftotext/pandoc
├─ Intelligent parsing + restructuring → AnyGen upload + doc operation
├─ Data analysis from spreadsheet → AnyGen upload + data_analysis operation
├─ Document is a web page → use web_fetch tool (see nimclaw-web-fetch skill)
└─ Document is a Feishu cloud doc → use feishu skill
```

## Prerequisites

- AnyGen skill must be installed (`nimclaw skills install anygen`)
- `ANYGEN_API_KEY` must be configured
