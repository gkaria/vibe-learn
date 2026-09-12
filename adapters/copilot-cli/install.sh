#!/bin/bash
# adapters/copilot-cli/install.sh — GitHub Copilot CLI hook and skill installer
set -euo pipefail

if [ "${1:-}" = "--global" ]; then
  MODE=global
  VIBE_LEARN_DIR="${2:-}"
  TARGET_DIR="$HOME"
else
  MODE=project
  VIBE_LEARN_DIR="${1:-}"
  TARGET_DIR="${2:-$(pwd)}"
fi

if [ -z "$VIBE_LEARN_DIR" ]; then
  echo "ERROR: VIBE_LEARN_DIR not provided." >&2
  exit 1
fi

ADAPTER_DIR="$VIBE_LEARN_DIR/adapters/copilot-cli"
SKILLS=(learn digest quiz explain vibe-learn)
if [ "$MODE" = global ]; then
  COPILOT_DIR="${COPILOT_HOME:-$HOME/.copilot}"
  HOOKS_DIR="$COPILOT_DIR/hooks"
  SKILLS_DIR="$COPILOT_DIR/skills"
  HOOK_COMMAND="$HOOKS_DIR/vibe-learn.sh"
else
  COPILOT_DIR="$TARGET_DIR/.github"
  HOOKS_DIR="$COPILOT_DIR/hooks"
  SKILLS_DIR="$COPILOT_DIR/skills"
  HOOK_COMMAND=".github/hooks/vibe-learn.sh"
fi
HOOKS_FILE="$HOOKS_DIR/vibe-learn.json"
SHIM_FILE="$HOOKS_DIR/vibe-learn.sh"

# Refuse collisions before writing anything. Re-running our own install is safe.
if [ -e "$HOOKS_FILE" ] && ! grep -q 'vibe-learn.sh' "$HOOKS_FILE"; then
  echo "ERROR: $HOOKS_FILE already exists and is not managed by vibe-learn." >&2
  exit 1
fi
if [ -e "$SHIM_FILE" ] && ! grep -q 'GitHub Copilot CLI payload shim' "$SHIM_FILE"; then
  echo "ERROR: $SHIM_FILE already exists and is not managed by vibe-learn." >&2
  exit 1
fi
for skill in "${SKILLS[@]}"; do
  file="$SKILLS_DIR/$skill/SKILL.md"
  if [ -e "$file" ] && ! grep -q 'vibe-learn copilot-cli adapter' "$file"; then
    echo "ERROR: $file already exists and is not managed by vibe-learn." >&2
    exit 1
  fi
done

mkdir -p "$HOOKS_DIR" "$SKILLS_DIR"
cp "$ADAPTER_DIR/hooks/vibe-learn.sh" "$SHIM_FILE"
chmod +x "$SHIM_FILE"

# POSIX-quote the command so install paths containing spaces or metacharacters remain literal.
shell_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
jq --arg cmd "$(shell_quote "$HOOK_COMMAND")" --arg dir "$VIBE_LEARN_DIR" '.hooks |= map_values(map(.bash = $cmd | .env.VIBE_LEARN_INSTALL_DIR = $dir))' \
  "$ADAPTER_DIR/hooks.json" > "$HOOKS_FILE"

for skill in "${SKILLS[@]}"; do
  mkdir -p "$SKILLS_DIR/$skill"
  cp "$ADAPTER_DIR/skills/$skill/SKILL.md" "$SKILLS_DIR/$skill/SKILL.md"
done

if [ "$MODE" = global ]; then
  echo "✓ GitHub Copilot CLI hooks installed ($HOOKS_FILE)"
  echo "✓ Skills installed ($SKILLS_DIR/{learn,digest,quiz,explain,vibe-learn}/SKILL.md)"
else
  echo "✓ GitHub Copilot CLI hooks installed (.github/hooks/vibe-learn.json → .github/hooks/vibe-learn.sh)"
  echo "✓ Skills installed (.github/skills/{learn,digest,quiz,explain,vibe-learn}/SKILL.md)"
fi
echo "  Invoke them in a Copilot prompt as: Use /learn, Use /digest, Use /quiz, or Use /explain."

if [ -w "$VIBE_LEARN_DIR/scripts" ]; then
  chmod +x "$VIBE_LEARN_DIR/scripts/"*.sh 2>/dev/null || true
fi

if [ "$MODE" = project ]; then
  GITIGNORE="$TARGET_DIR/.gitignore"
  if [ -f "$GITIGNORE" ]; then
    if ! grep -q '\.vibe-learn' "$GITIGNORE"; then
      printf '\n# vibe-learn session logs\n.vibe-learn/\n' >> "$GITIGNORE"
      echo "✓ Added .vibe-learn/ to .gitignore"
    else
      echo "✓ .gitignore already excludes .vibe-learn/"
    fi
  else
    printf '# vibe-learn session logs\n.vibe-learn/\n' > "$GITIGNORE"
    echo "✓ Created .gitignore with .vibe-learn/"
  fi
fi
