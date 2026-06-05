#!/bin/bash
# audio-prep.sh — Find the latest NotebookLM pack and reduce the upload to one step.

set -euo pipefail

TARGET_DIR="${1:-$(pwd)}"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

EXPORTS_DIR="$TARGET_DIR/.vibe-learn/briefing/exports"

if [ ! -d "$EXPORTS_DIR" ]; then
  echo "No session briefing exports found for $(basename "$TARGET_DIR")." >&2
  echo "Run 'vibe-learn briefing' first, or wait for the next agent response." >&2
  exit 1
fi

PACK=$(find "$EXPORTS_DIR" -maxdepth 1 -name '*-notebooklm-pack.md' -type f | sort -r | head -1)

if [ -z "$PACK" ]; then
  echo "No NotebookLM pack found in $EXPORTS_DIR." >&2
  echo "Run 'vibe-learn briefing' to generate one." >&2
  exit 1
fi

echo "NotebookLM pack: $PACK"
echo ""

# Copy pack path to clipboard (macOS pbcopy, Linux xclip/xdg-clipboard)
COPIED=false
if command -v pbcopy >/dev/null 2>&1; then
  printf '%s' "$PACK" | pbcopy
  echo "✓ Pack path copied to clipboard"
  COPIED=true
elif command -v xclip >/dev/null 2>&1; then
  printf '%s' "$PACK" | xclip -selection clipboard 2>/dev/null
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
