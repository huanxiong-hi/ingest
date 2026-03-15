# Ingest — Content Extraction Tool

## Purpose

Extract text from various file formats (.doc, .pdf, .html, URLs, etc.) into plain text, stored in `_staging/` directory with a `_manifest.md` for LLM routing decisions.

## Usage

```bash
# Basic: extract files
ingest file1.doc file2.pdf "https://example.com"

# With target directory scanning (recommended): indexes existing content for overlap detection
ingest --target docs/project/ file1.doc file2.doc
```

## --target parameter

When specified, `_manifest.md` includes a heading index of all `.md` files in the target directory. The LLM can spot overlap between new and existing content at a glance — without opening every target file.

## Extractor interface

Each extractor is a standalone `.sh` file in `scripts/extractors/`:
- **Input:** `$1` = file path
- **Output:** Plain text to stdout
- **Exit codes:** 0 = success, 2 = needs LLM visual read (.needs-visual), 1 = tool missing/error

### Supported formats

| Extension | Extractor | Dependencies |
|-----------|-----------|-------------|
| .doc / .docx / .rtf | textutil | macOS built-in |
| .pdf | pdftotext → OCR → LLM visual read fallback | poppler (optional), tesseract (optional) |
| .html | pandoc → textutil fallback | pandoc (optional) |
| .png / .jpg / .jpeg / .webp / .tiff / .bmp | tesseract OCR → LLM visual read fallback | tesseract + tesseract-lang |
| URL | readability-cli → pandoc → curl fallback | readability-cli (optional) |
| .md | cat | None |
| .mp4 | whisper | openai-whisper (required) |

### Adding/removing formats

| Action | How |
|--------|-----|
| Add .epub | Create `scripts/extractors/epub.sh` with a pandoc command |
| Remove .doc | Delete `scripts/extractors/doc.sh` |
| List formats | Run `ingest` (no arguments) |

## Integration workflow

When integrating files/URLs into a project, follow this flow:

1. **Extract** — Run `ingest --target <target-dir> file1.doc file2.pdf https://...`
1b. **Visual Read** — If `_manifest.md` has a **Needs Visual Read** section:
    - Read original PDF/image files using the LLM's native vision support
    - For PDFs over 20 pages, read in batches (pages: "1-20", "21-40"...)
    - Write extracted content to `_staging/XX_name.txt` replacing `.needs-visual` files
2. **Route** — Read only `_staging/_manifest.md` (filenames + 5-line previews + target index) to decide routing. Do not read full staging files at this step
3. **Check overlap** — Compare new content against the target directory index in the manifest. List overlaps and confirm before merging
4. **Integrate** — Process staging files one at a time: Read → format to match project → Write/Edit to target. Do not load multiple staging files simultaneously
5. **Clean up** — `rm -rf _staging/` after confirmation

### Token optimization (~74% savings)

| Layer | Who | Token cost |
|-------|-----|-----------|
| Layer 0 | `ingest` scripts extract text | Zero (script execution) |
| Layer 1 | LLM reads only `_manifest.md` for routing | Minimal |
| Layer 2 | LLM processes staging files one by one, context compression releases completed files | Normal |

### Rules

- Do not use Agent subprocesses to shuttle large text (copying to sub-context and back = 2x waste)
- Do not read binary files directly — always run `ingest` first
- Do not load multiple staging files simultaneously (process one at a time, let context compression release completed files)
