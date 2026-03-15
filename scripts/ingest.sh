#!/bin/bash
# Content Ingestion Pipeline — Layer 0: Extract
# Usage: ingest [--target <dir>] <file1> <file2> <url1> ...
# Output: _staging/ directory with extracted text + _manifest.md

set -euo pipefail

# Resolve symlinks to find the real script location
SOURCE="$0"
while [[ -L "$SOURCE" ]]; do
    DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
EXTRACTORS_DIR="$SCRIPT_DIR/extractors"
STAGING_DIR="./_staging"
TARGET_DIR=""

# --- Helpers ---

die() { echo "ERROR: $*" >&2; exit 1; }

get_extractor() {
    local input="$1"
    # URL detection
    if [[ "$input" =~ ^https?:// ]]; then
        echo "$EXTRACTORS_DIR/web.sh"
        return
    fi
    # File extension
    local ext="${input##*.}"
    ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
    local extractor="$EXTRACTORS_DIR/${ext}.sh"
    if [[ -f "$extractor" ]]; then
        echo "$extractor"
    else
        echo ""
    fi
}

assess_quality() {
    local file="$1"
    local lines="$(wc -l < "$file" | tr -d ' ')"
    local chars="$(tr -d '[:space:]' < "$file" | wc -c | tr -d ' ')"
    if [[ "$lines" -gt 10 && "$chars" -gt 100 ]]; then
        echo "good"
    else
        echo "sparse"
    fi
}

generate_manifest() {
    local manifest="$STAGING_DIR/_manifest.md"
    cat > "$manifest" <<'HEADER'
# Staging Manifest

## New Content

| # | File | Lines | Quality | Preview |
|---|------|-------|---------|---------|
HEADER

    local i=0
    for f in "$STAGING_DIR"/*.txt; do
        [[ -f "$f" ]] || continue
        i=$((i + 1))
        local basename="$(basename "$f")"
        local lines="$(wc -l < "$f" | tr -d ' ')"
        local quality="$(assess_quality "$f")"
        # First 5 non-empty lines, joined with " / "
        local preview="$(grep -m 5 '.' "$f" | tr '\n' '/' | sed 's|/| / |g; s| / $||')"
        # Truncate preview to 120 chars
        if [[ ${#preview} -gt 120 ]]; then
            preview="${preview:0:117}..."
        fi
        echo "| $i | $basename | $lines | $quality | $preview |" >> "$manifest"
    done

    # Add summary line
    local total_files="$i"
    local total_lines=0
    for f in "$STAGING_DIR"/*.txt; do
        [[ -f "$f" ]] || continue
        total_lines=$((total_lines + $(wc -l < "$f" | tr -d ' ')))
    done
    echo "" >> "$manifest"
    echo "**Total: $total_files files, $total_lines lines**" >> "$manifest"

    # Needs Visual Read section — scan for .needs-visual files
    local has_visual=0
    for f in "$STAGING_DIR"/*.needs-visual; do
        [[ -f "$f" ]] || continue
        if [[ $has_visual -eq 0 ]]; then
            echo "" >> "$manifest"
            echo "## Needs Visual Read" >> "$manifest"
            echo "" >> "$manifest"
            echo "> Claude: use Read tool on these files (supports PDF/image natively)" >> "$manifest"
            echo "" >> "$manifest"
            echo "| File | Original Path | Pages |" >> "$manifest"
            echo "|------|--------------|-------|" >> "$manifest"
            has_visual=1
        fi
        local vbasename="$(basename "$f")"
        local orig_path="$(grep 'NEEDS_VISUAL_READ' "$f" | sed 's/\[NEEDS_VISUAL_READ\] //')"
        local pages="$(grep 'PAGES' "$f" | sed 's/\[PAGES\] //' || echo '-')"
        [[ -z "$pages" ]] && pages="-"
        echo "| $vbasename | $orig_path | $pages |" >> "$manifest"
    done

    # If --target was specified, scan target directory for existing headings
    if [[ -n "$TARGET_DIR" && -d "$TARGET_DIR" ]]; then
        echo "" >> "$manifest"
        echo "---" >> "$manifest"
        echo "" >> "$manifest"
        echo "## Target Directory Index" >> "$manifest"
        echo "" >> "$manifest"
        echo "> Existing headings in \`$TARGET_DIR\` — check for overlap with new content." >> "$manifest"
        echo "" >> "$manifest"

        local md_count=0
        for md_file in "$TARGET_DIR"/*.md; do
            [[ -f "$md_file" ]] || continue
            md_count=$((md_count + 1))
            if [[ $md_count -gt 50 ]]; then
                local total_md="$(ls "$TARGET_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')"
                echo "> Showing 50 of $total_md files. Use grep for targeted overlap search." >> "$manifest"
                break
            fi
            local md_basename="$(basename "$md_file")"
            echo "### $md_basename" >> "$manifest"
            # Extract ## and ### headings
            grep -n '^##\{1,2\} ' "$md_file" | while IFS= read -r line; do
                echo "- $line" >> "$manifest"
            done
            echo "" >> "$manifest"
        done
    fi
}

# --- Main ---

# Parse --target option
if [[ "${1:-}" == "--target" ]]; then
    [[ $# -ge 2 ]] || die "--target requires a directory argument"
    TARGET_DIR="$2"
    [[ -d "$TARGET_DIR" ]] || die "Target directory not found: $TARGET_DIR"
    shift 2
fi

if [[ $# -eq 0 ]]; then
    echo "Usage: ingest [--target <dir>] <file1> [file2] [url1] ..."
    echo ""
    echo "Options:"
    echo "  --target <dir>  Scan target directory headings for overlap detection"
    echo ""
    echo "Supported formats:"
    for ext_script in "$EXTRACTORS_DIR"/*.sh; do
        [[ -f "$ext_script" ]] || continue
        echo "  .$(basename "${ext_script%.sh}")"
    done
    echo "  URLs (https://...)"
    exit 0
fi

# Create staging directory
mkdir -p "$STAGING_DIR"

counter=0
success=0
failed=0
visual=0

for input in "$@"; do
    counter=$((counter + 1))
    padded="$(printf '%02d' "$counter")"

    # Determine output filename
    if [[ "$input" =~ ^https?:// ]]; then
        # Use domain + path slug for URLs
        slug="$(echo "$input" | sed 's|https\?://||; s|[^a-zA-Z0-9\u4e00-\u9fff]|_|g; s|__*|_|g; s|_$||')"
        outname="${padded}_${slug}.txt"
    else
        [[ -f "$input" ]] || { echo "SKIP: $input (file not found)"; failed=$((failed + 1)); continue; }
        basename_no_ext="$(basename "${input%.*}")"
        outname="${padded}_${basename_no_ext}.txt"
    fi

    extractor="$(get_extractor "$input")"
    if [[ -z "$extractor" ]]; then
        ext="${input##*.}"
        echo "SKIP: $input (no extractor for .$ext)"
        echo "  → Create $EXTRACTORS_DIR/${ext}.sh to add support"
        failed=$((failed + 1))
        continue
    fi

    # Run extractor
    outpath="$STAGING_DIR/$outname"
    set +e
    bash "$extractor" "$input" > "$outpath" 2>/dev/null
    ext_code=$?
    set -e

    if [[ $ext_code -eq 0 ]]; then
        lines="$(wc -l < "$outpath" | tr -d ' ')"
        echo "  OK: $input → $outname ($lines lines)"
        success=$((success + 1))
    elif [[ $ext_code -eq 2 ]]; then
        # Rename to .needs-visual for manifest
        visual_path="${outpath%.txt}.needs-visual"
        mv "$outpath" "$visual_path"
        echo "  VISUAL: $input → needs Claude visual read"
        visual=$((visual + 1))
    else
        echo "FAIL: $input (extractor error)"
        rm -f "$outpath"
        failed=$((failed + 1))
    fi
done

# Generate manifest
generate_manifest

echo ""
echo "Done: $success extracted, $visual visual-read, $failed skipped → _staging/"
[[ -n "$TARGET_DIR" ]] && echo "Target index: $TARGET_DIR (check _manifest.md for overlap)"
echo "Next: Claude reads _staging/_manifest.md for routing"
