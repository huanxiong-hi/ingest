#!/bin/bash
# Extract text from .pdf — pdftotext → OCR → Claude visual fallback

check_quality() {
    local text="$1"
    [[ "$(echo "$text" | tr -d '[:space:]' | wc -c | tr -d ' ')" -gt 20 ]]
}

# Layer 1: pdftotext (fastest, zero OCR cost)
if command -v pdftotext &>/dev/null; then
    text="$(pdftotext -layout "$1" - 2>/dev/null)"
    if check_quality "$text"; then
        echo "$text"
        exit 0
    fi
fi

# Layer 2: tesseract OCR
if command -v tesseract &>/dev/null && command -v pdftoppm &>/dev/null; then
    LANGS="chi_sim+eng"
    if ! tesseract --list-langs 2>&1 | grep -q "chi_sim"; then
        LANGS="eng"
    fi
    TMPDIR="$(mktemp -d)"
    trap 'rm -rf "$TMPDIR"' EXIT
    pdftoppm -png "$1" "$TMPDIR/page"
    ocr_text=""
    for img in "$TMPDIR"/page-*.png; do
        [[ -f "$img" ]] || continue
        ocr_text+="$(tesseract "$img" stdout -l "$LANGS" 2>/dev/null)"
        ocr_text+=$'\n'
    done
    if check_quality "$ocr_text"; then
        echo "$ocr_text"
        exit 0
    fi
fi

# Layer 3: All failed → signal Claude to use visual Read
ABS_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
echo "[NEEDS_VISUAL_READ] $ABS_PATH"
# Get page count if pdfinfo available
if command -v pdfinfo &>/dev/null; then
    pages="$(pdfinfo "$1" 2>/dev/null | grep '^Pages:' | awk '{print $2}')"
    [[ -n "$pages" ]] && echo "[PAGES] $pages"
fi
exit 2
