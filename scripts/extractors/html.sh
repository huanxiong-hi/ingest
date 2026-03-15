#!/bin/bash
# Extract text from local .html files
if command -v pandoc &>/dev/null; then
    pandoc -f html -t markdown "$1"
else
    textutil -convert txt -stdout "$1"
fi
