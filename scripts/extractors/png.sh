#!/bin/bash
# Extract text from images via OCR, fallback to Claude visual read
# Supports: .png, .jpg, .jpeg, .webp, .tiff, .bmp
# Requires: brew install tesseract tesseract-lang

if command -v tesseract &>/dev/null; then
    LANGS="chi_sim+eng"
    if ! tesseract --list-langs 2>&1 | grep -q "chi_sim"; then
        LANGS="eng"
    fi
    text="$(tesseract "$1" stdout -l "$LANGS" 2>/dev/null)"
    if [[ "$(echo "$text" | tr -d '[:space:]' | wc -c | tr -d ' ')" -gt 10 ]]; then
        echo "$text"
        exit 0
    fi
fi

# OCR failed or not installed → signal Claude visual read
ABS_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
echo "[NEEDS_VISUAL_READ] $ABS_PATH"
exit 2
