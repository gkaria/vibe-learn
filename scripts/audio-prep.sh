#!/bin/bash
# audio-prep.sh — Find the latest NotebookLM pack and reduce the upload to one step.

set -euo pipefail

TARGET_DIR=""
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      echo "Usage: vibe-learn audio-prep [target-dir]"
      echo "Finds the latest NotebookLM pack (building the briefing when there is none) and walks through the upload."
      exit 0
      ;;
    -*)
      echo "ERROR: Unknown audio-prep flag: $arg" >&2
      exit 1
      ;;
    *)
      if [ -n "$TARGET_DIR" ]; then
        echo "ERROR: audio-prep accepts at most one target directory." >&2
        exit 1
      fi
      TARGET_DIR="$arg"
      ;;
  esac
done
TARGET_DIR="${TARGET_DIR:-$(pwd)}"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORTS_DIR="$TARGET_DIR/.vibe-learn/briefing/exports"

# Newest by modification time: same-day filenames differ only by session id.
latest_pack() {
  ls -1t "$EXPORTS_DIR"/*-notebooklm-pack.md 2>/dev/null | head -1 || true
}

PACK=$(latest_pack)
if [ -z "$PACK" ]; then
  echo "No NotebookLM pack yet; building the session briefing first." >&2
  if ! bash "$SCRIPT_DIR/briefing.sh" "$TARGET_DIR" >&2; then
    echo "The briefing failed (see above), so there is no pack to upload yet." >&2
    exit 1
  fi
  PACK=$(latest_pack)
fi

if [ -z "$PACK" ]; then
  echo "No session log found for $(basename "$TARGET_DIR"), so there is no pack to upload." >&2
  echo "Work a session with vibe-learn installed, then run 'vibe-learn audio-prep' again." >&2
  exit 1
fi

echo "NotebookLM pack: $PACK"
echo ""

# Copy pack path to clipboard (macOS pbcopy, Linux xclip). Optional: a missing
# or inaccessible clipboard must not abort the rest of the helper.
COPIED=false
if command -v pbcopy >/dev/null 2>&1 && printf '%s' "$PACK" | pbcopy 2>/dev/null; then
  echo "✓ Pack path copied to clipboard"
  COPIED=true
elif command -v xclip >/dev/null 2>&1 && printf '%s' "$PACK" | xclip -selection clipboard 2>/dev/null; then
  echo "✓ Pack path copied to clipboard"
  COPIED=true
fi

echo ""
echo "Next steps:"
echo "  1. Open NotebookLM:  https://notebooklm.google.com"
echo "  2. Create a new notebook"
echo "  3. Add source → Upload file → select the pack above"
if [ "$COPIED" = "false" ]; then
  echo "     Path: $PACK"
fi
echo "  4. Generate an Audio Overview"
echo ""
echo "The pack opens with the brief for the overview. If NotebookLM asks you to"
echo "customise it, paste the same text:"
echo ""
# The pack's first paragraph, after its title.
awk 'NR > 1 && NF { print; found = 1; next } found { exit }' "$PACK" | fold -s -w 76 | sed 's/^/  /'

# Open NotebookLM and the exports folder
OPENED_BROWSER=false
if command -v open >/dev/null 2>&1; then
  open "https://notebooklm.google.com" 2>/dev/null && OPENED_BROWSER=true
  open "$EXPORTS_DIR" 2>/dev/null || true
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "https://notebooklm.google.com" 2>/dev/null && OPENED_BROWSER=true
fi

if [ "$OPENED_BROWSER" = "true" ]; then
  echo ""
  echo "✓ NotebookLM opened in browser"
fi
