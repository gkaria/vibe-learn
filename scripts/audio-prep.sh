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
RECORDS_DIR="$TARGET_DIR/.vibe-learn/briefing/.sessions"

# The pack of the newest session by start time, then session id, from the
# records briefing.sh writes, so rebuilding an older session's pack never
# makes it the latest. Packs from before records existed: newest mtime.
latest_pack() {
  local slug
  for slug in $(cat "$RECORDS_DIR"/* 2>/dev/null \
      | jq -Rnr '[inputs | fromjson? | objects | select(.slug | type == "string")]
                 | sort_by(.started_at // "", .session_id // "") | reverse | .[].slug' 2>/dev/null); do
    if [ -f "$EXPORTS_DIR/$slug-notebooklm-pack.md" ]; then
      printf '%s\n' "$EXPORTS_DIR/$slug-notebooklm-pack.md"
      return
    fi
  done
  ls -1t "$EXPORTS_DIR"/*-notebooklm-pack.md 2>/dev/null | sed -n 1p || true
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
echo "Paste this prompt when asked to customise the overview:"
echo ""
echo "  Create a maintainer-focused audio overview. Explain what changed, why it"
echo "  matters, what to inspect first, and what could break. Assume the listener"
echo "  owns this codebase and needs enough technical depth to support it."

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
