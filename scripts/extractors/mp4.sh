#!/bin/bash
# Extract audio transcription from video files
# Requires: whisper (pip install openai-whisper) or whisper.cpp

if command -v whisper &>/dev/null; then
    whisper "$1" --output_format txt --output_dir /tmp/whisper_out 2>/dev/null
    cat "/tmp/whisper_out/$(basename "${1%.*}").txt"
    rm -rf /tmp/whisper_out
else
    echo "[mp4 extractor] whisper not installed."
    echo "Install: pip install openai-whisper"
    echo "Or: brew install whisper-cpp"
    exit 1
fi
