#!/bin/bash
# adapters/cursor/install.sh — Cursor-specific install logic
# Called by scripts/install.sh and scripts/setup.sh.
#
# Usage:
#   adapters/cursor/install.sh --global <VIBE_LEARN_DIR>
#   adapters/cursor/install.sh <VIBE_LEARN_DIR> <TARGET_DIR>
#
# Installs one shim script (hooks/vibe-learn.sh) that translates Cursor hook
# payloads for the core scripts, merges vibe-learn entries into hooks.json
# without touching other hooks, and copies the skills: /learn, /digest, /quiz,
# /explain (slash-command style, explicit invocation only) plus the vibe-learn
# skill for natural-language requests. Cursor has folded slash commands into
# skills, so nothing is written to .cursor/commands/.
#
# Global:  ~/.cursor/hooks.json, ~/.cursor/hooks/vibe-learn.sh, ~/.cursor/skills/<name>/SKILL.md
# Project: .cursor/hooks.json,   .cursor/hooks/vibe-learn.sh,   .cursor/skills/<name>/SKILL.md

set -euo pipefail

MODE=""
VIBE_LEARN_DIR=""
TARGET_DIR=""

if [ "${1:-}" = "--global" ]; then
  MODE="global"
  VIBE_LEARN_DIR="${2:-}"
  TARGET_DIR="$HOME"
else
  MODE="project"
  VIBE_LEARN_DIR="${1:-}"
  TARGET_DIR="${2:-$(pwd)}"
fi

if [ -z "$VIBE_LEARN_DIR" ]; then
  echo "ERROR: VIBE_LEARN_DIR not provided." >&2
  exit 1
fi

ADAPTER_DIR="$VIBE_LEARN_DIR/adapters/cursor"
HOOKS_TEMPLATE="$ADAPTER_DIR/hooks.json"
SHIM_SOURCE="$ADAPTER_DIR/hooks/vibe-learn.sh"
SKILLS_SOURCE="$ADAPTER_DIR/skills"
SKILLS=(learn digest quiz explain vibe-learn)

if [ "$MODE" = "global" ]; then
  CURSOR_DIR="$HOME/.cursor"
  # User hooks run from ~/.cursor; an absolute path is unambiguous either way.
  HOOK_COMMAND="$CURSOR_DIR/hooks/vibe-learn.sh"
else
  CURSOR_DIR="$TARGET_DIR/.cursor"
  # Project hooks run from the project root; Cursor documents this relative form.
  HOOK_COMMAND=".cursor/hooks/vibe-learn.sh"
fi

HOOKS_DIR="$CURSOR_DIR/hooks"
SKILLS_DIR="$CURSOR_DIR/skills"
HOOKS_FILE="$CURSOR_DIR/hooks.json"
SHIM_FILE="$HOOKS_DIR/vibe-learn.sh"

mkdir -p "$HOOKS_DIR" "$SKILLS_DIR"

# --- Shim: bake in the install directory (awk, so &, | and / in paths are literal) ---
awk -v dir="$VIBE_LEARN_DIR" '{
  idx = index($0, "VIBE_LEARN_DIR_PLACEHOLDER")
  if (idx > 0) {
    $0 = substr($0, 1, idx - 1) dir substr($0, idx + length("VIBE_LEARN_DIR_PLACEHOLDER"))
  }
  print
}' "$SHIM_SOURCE" > "$SHIM_FILE"
chmod +x "$SHIM_FILE"

# --- hooks.json: merge our entries, leave everything else alone ---
OUR_HOOKS="$(jq --arg cmd "$HOOK_COMMAND" '.hooks | map_values(map(.command = $cmd))' "$HOOKS_TEMPLATE")"

if [ -f "$HOOKS_FILE" ]; then
  if ! jq -e 'type == "object"' "$HOOKS_FILE" >/dev/null 2>&1; then
    echo "ERROR: $HOOKS_FILE is not valid JSON. Fix or remove it, then re-run." >&2
    exit 1
  fi
  EXISTING="$(cat "$HOOKS_FILE")"
else
  EXISTING='{"version":1,"hooks":{}}'
fi

# A hook entry is ours if its command ends in /vibe-learn.sh. Replace ours, keep theirs.
MERGED="$(printf '%s' "$EXISTING" | jq --argjson ours "$OUR_HOOKS" '
  .version = (.version // 1)
  | .hooks = (.hooks // {})
  | reduce ($ours | to_entries[]) as $e (.;
      .hooks[$e.key] = (
        ((.hooks[$e.key] // []) | map(select((.command // "") | endswith("/vibe-learn.sh") | not)))
        + $e.value
      )
    )')"

TMP="$(mktemp "$CURSOR_DIR/.hooks.XXXXXX")"
printf '%s\n' "$MERGED" > "$TMP"
mv "$TMP" "$HOOKS_FILE"

# --- Skills ---
for skill in "${SKILLS[@]}"; do
  mkdir -p "$SKILLS_DIR/$skill"
  cp "$SKILLS_SOURCE/$skill/SKILL.md" "$SKILLS_DIR/$skill/SKILL.md"
done

if [ "$MODE" = "global" ]; then
  echo "✓ Cursor hooks installed ($HOOKS_FILE → $SHIM_FILE)"
  echo "✓ Skills installed ($SKILLS_DIR/{learn,digest,quiz,explain,vibe-learn}/SKILL.md)"
else
  echo "✓ Cursor hooks installed (.cursor/hooks.json → .cursor/hooks/vibe-learn.sh)"
  echo "✓ Skills installed (.cursor/skills/{learn,digest,quiz,explain,vibe-learn}/SKILL.md)"
  echo "  Project hooks run once this workspace is trusted in Cursor."
fi

if [ -w "$VIBE_LEARN_DIR/scripts" ]; then
  chmod +x "$VIBE_LEARN_DIR/scripts/"*.sh 2>/dev/null || true
fi
echo "✓ Scripts are executable"

if [ "$MODE" = "project" ]; then
  GITIGNORE="$TARGET_DIR/.gitignore"
  if [ -f "$GITIGNORE" ]; then
    if ! grep -q '\.vibe-learn' "$GITIGNORE"; then
      echo "" >> "$GITIGNORE"
      echo "# vibe-learn session logs" >> "$GITIGNORE"
      echo ".vibe-learn/" >> "$GITIGNORE"
      echo "✓ Added .vibe-learn/ to .gitignore"
    else
      echo "✓ .gitignore already excludes .vibe-learn/"
    fi
  else
    echo "# vibe-learn session logs" > "$GITIGNORE"
    echo ".vibe-learn/" >> "$GITIGNORE"
    echo "✓ Created .gitignore with .vibe-learn/"
  fi
fi
