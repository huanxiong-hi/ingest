#!/bin/bash
# Extract article text from a URL
# Tries: readability-cli → pandoc → raw curl
URL="$1"

if command -v readable &>/dev/null; then
    # readability-cli outputs clean article text
    readable "$URL" --quiet 2>/dev/null | pandoc -f html -t plain 2>/dev/null || \
    readable "$URL" --quiet 2>/dev/null
elif command -v pandoc &>/dev/null; then
    curl -sL "$URL" | pandoc -f html -t plain
else
    # Last resort: raw HTML with tags stripped
    curl -sL "$URL" | sed 's/<[^>]*>//g'
fi
