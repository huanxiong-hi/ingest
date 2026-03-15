# ingest

Content extraction pipeline for AI coding agents.

Turn any file or URL into clean text that your AI agent can actually work with — PDF, DOCX, HTML, images, video, web pages. One command, zero tokens wasted on extraction.

## The idea

The code is ~350 lines of bash. That's not where the value is.

The value is in the **architecture pattern**: separating what scripts should do from what LLMs should do.

```
┌─────────────────────────────────────┐
│         What the LLM does           │
│  Route content, detect overlap,     │
│  reformat, integrate into project   │
│  (judgment, language, structure)     │
├─────────────────────────────────────┤
│            Guardrail                │
│  _manifest.md — LLM sees filenames  │
│  + 5-line previews + target index   │
│  (never reads raw staging files     │
│   until integration step)           │
├─────────────────────────────────────┤
│       What scripts do               │
│  Extract text from binaries,        │
│  run OCR, fetch web pages,          │
│  assess quality, build manifest     │
│  (mechanical, deterministic, free)  │
└─────────────────────────────────────┘
```

Using an LLM to extract text from a PDF is like hiring a Michelin-star chef to wash vegetables. The chef's talent is wasted, and the vegetables don't come out any cleaner. Scripts handle extraction; the LLM handles decisions.

Every format degrades gracefully — PDFs try text extraction first, then OCR, then signal the LLM to use its own vision. No dependency is truly required; the pipeline always produces *something*.

This separation saves ~74% of token cost compared to feeding raw files directly to the LLM.

## How it works

**Three layers, each doing what it's best at:**

| Layer | Who | Token cost | What happens |
|-------|-----|-----------|--------------|
| 0 — Extract | `ingest.sh` | Zero | Scripts extract text, run OCR, fetch web content |
| 1 — Route | LLM | Minimal | LLM reads only `_manifest.md` (~50-100 lines) to decide where content goes |
| 2 — Integrate | LLM | Normal | LLM processes staging files one at a time, with context compression releasing completed work |

## Install

```bash
git clone https://github.com/huanxiong-hi/ingest.git && cd ingest
mkdir -p ~/.local/bin
ln -sf "$(pwd)/scripts/ingest.sh" ~/.local/bin/ingest
brew install poppler tesseract pandoc  # core deps (optional, graceful fallback)
```

Make sure `~/.local/bin` is in your `PATH`. Add to your shell profile if needed: `export PATH="$HOME/.local/bin:$PATH"`

Optional dependencies:

```bash
brew install tesseract-lang          # Chinese OCR support
npm install -g @nicepkg/readability-cli  # best web extraction
pip install openai-whisper           # video transcription
```

## Usage

```bash
# Extract files into _staging/
ingest report.pdf notes.docx "https://example.com/article"

# With target directory scanning (recommended)
# Indexes existing headings in target dir for overlap detection
ingest --target docs/project/ report.pdf notes.docx

# Show supported formats
ingest
```

### What `--target` does

When you specify `--target <dir>`, the manifest includes a heading index of all `.md` files in that directory. Your LLM can then spot content overlap at a glance — without opening every target file.

### Output structure

```
_staging/
├── 01_report.txt              # Extracted text (good quality)
├── 02_notes.txt               # Extracted text
├── 03_example_com_article.txt  # Web page content
├── 04_photo.needs-visual       # Needs LLM visual read (OCR failed)
└── _manifest.md               # Routing manifest for the LLM
```

## Supported formats

| Format | Dependencies |
|--------|-------------|
| `.pdf` | `poppler` (optional), `tesseract` (optional) |
| `.doc` `.docx` `.rtf` | None (macOS built-in) |
| `.html` | `pandoc` (optional) |
| `.md` | None |
| `.png` `.jpg` `.jpeg` `.webp` `.tiff` `.bmp` | `tesseract` (optional) |
| URL (`https://...`) | `readability-cli` (optional) |
| `.mp4` | `openai-whisper` or `whisper-cpp` |

## Writing a custom extractor

Each extractor is a standalone shell script in `scripts/extractors/`. Drop a `.sh` file, and the filename becomes the supported extension — no registration, no config.

```bash
# scripts/extractors/epub.sh
#!/bin/bash
pandoc -f epub -t plain "$1"
```

To remove a format, delete its extractor file. Linux users: replace `textutil` with `pandoc` or `libreoffice` in the relevant extractors.

## Working with Claude Code

The scripts handle extraction, but the real workflow lives in `CLAUDE.md` — a behavior file that tells Claude Code *how* to use the extracted content:

1. **Extract** — Run `ingest --target <dir> files...`
2. **Visual read** — If any `.needs-visual` files exist, read the originals using Claude's native PDF/image support
3. **Route** — Read only `_manifest.md` to decide where content goes (not the full staging files)
4. **Check overlap** — Compare new content against the target directory index in the manifest
5. **Integrate** — Process staging files one at a time, formatting to match the target project
6. **Clean up** — `rm -rf _staging/` after confirmation

**Guardrails** — The `CLAUDE.md` enforces three rules to keep token costs low: no loading multiple staging files at once (let context compression release completed work), no Agent subprocesses to shuttle large text (2x token waste), no reading binaries directly (always extract first). Adapt the `CLAUDE.md` to your own workflow — it's the control layer that makes the pipeline useful, not just functional.

## License

MIT
