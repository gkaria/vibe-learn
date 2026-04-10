#!/bin/bash
# setup.sh — curl-installable setup for vibe-learn
# Installs vibe-learn to ~/.vibe-learn/ and creates a CLI shim.
#
# Usage (from GitHub):
#   curl -fsSL https://raw.githubusercontent.com/gkaria/vibe-learn/main/scripts/setup.sh | bash
#
# Usage (local testing, no network):
#   bash /path/to/vibe-learn/scripts/setup.sh --local

set -euo pipefail

VIBE_LEARN_VERSION="0.5.1" # x-release-please-version
INSTALL_DIR="$HOME/.vibe-learn"
SHIM_DIR="$HOME/.local/bin"
SHIM_PATH="$SHIM_DIR/vibe-learn"
GITHUB_RAW="https://raw.githubusercontent.com/gkaria/vibe-learn/main"

LOCAL_MODE=false
if [ "${1:-}" = "--local" ]; then
  LOCAL_MODE=true
  # Resolve the repo root relative to this script
  LOCAL_SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

# --- Dependency check ---
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not found."
  echo "  macOS:  brew install jq"
  echo "  Linux:  apt-get install jq  (or equivalent)"
  exit 1
fi

if ! command -v curl &>/dev/null && [ "$LOCAL_MODE" = false ]; then
  echo "ERROR: curl is required but not found."
  exit 1
fi

download_file() {
  local url="$1"
  local dest="$2"
  # Retry to survive transient GitHub Raw throttling (HTTP 429) and network flakiness.
  curl -fsSL \
    --retry 8 \
    --retry-delay 2 \
    --retry-all-errors \
    -A "vibe-learn-setup/$VIBE_LEARN_VERSION" \
    "$url" -o "$dest"
}

# --- Version check ---
if [ -f "$INSTALL_DIR/VERSION" ]; then
  EXISTING_VERSION=$(cat "$INSTALL_DIR/VERSION")
  if [ "$EXISTING_VERSION" = "$VIBE_LEARN_VERSION" ] && [ "$LOCAL_MODE" = false ]; then
    echo "vibe-learn $VIBE_LEARN_VERSION is already installed. Nothing to do."
    echo "  To reinstall: bash $INSTALL_DIR/scripts/setup.sh --local"
    exit 0
  fi
  echo "Updating vibe-learn from $EXISTING_VERSION to $VIBE_LEARN_VERSION..."
else
  echo "Installing vibe-learn $VIBE_LEARN_VERSION to $INSTALL_DIR..."
fi

# --- Files to install ---
FILES=(
  "scripts/bootstrap.sh"
  "scripts/capture-prompt.sh"
  "scripts/observe.sh"
  "scripts/pause-summary.sh"
  "scripts/install.sh"
  "scripts/setup.sh"
  ".claude/commands/learn.md"
  ".claude/commands/digest.md"
  "config/defaults.json"
  "config/obsidian-defaults.json"
)

# --- Download or copy files ---
for FILE in "${FILES[@]}"; do
  DEST="$INSTALL_DIR/$FILE"
  mkdir -p "$(dirname "$DEST")"

  if [ "$LOCAL_MODE" = true ]; then
    cp "$LOCAL_SOURCE/$FILE" "$DEST"
  else
    download_file "$GITHUB_RAW/$FILE" "$DEST"
  fi
done

# --- Write VERSION ---
echo "$VIBE_LEARN_VERSION" > "$INSTALL_DIR/VERSION"

# --- Make scripts executable ---
chmod +x "$INSTALL_DIR/scripts/"*.sh

# --- Install CLI shim ---
mkdir -p "$SHIM_DIR"
cat > "$SHIM_PATH" <<'EOF'
#!/bin/bash
# Strip the "install" subcommand if present, pass remaining args
if [ "${1:-}" = "install" ]; then
  shift
fi
exec "$HOME/.vibe-learn/scripts/install.sh" "$@"
EOF
chmod +x "$SHIM_PATH"

echo "✓ vibe-learn $VIBE_LEARN_VERSION installed to $INSTALL_DIR"
echo "✓ CLI shim created at $SHIM_PATH"

# --- Register global hooks in ~/.claude/settings.json ---
register_global_hooks() {
  local CLAUDE_SETTINGS_DIR="$HOME/.claude"
  local GLOBAL_SETTINGS="$CLAUDE_SETTINGS_DIR/settings.json"
  local GLOBAL_COMMANDS_DIR="$CLAUDE_SETTINGS_DIR/commands"

  mkdir -p "$CLAUDE_SETTINGS_DIR"
  mkdir -p "$GLOBAL_COMMANDS_DIR"

  # Copy slash commands to global commands directory
  cp "$INSTALL_DIR/.claude/commands/learn.md" "$GLOBAL_COMMANDS_DIR/learn.md"
  cp "$INSTALL_DIR/.claude/commands/digest.md" "$GLOBAL_COMMANDS_DIR/digest.md"

  local HOOKS_JSON
  HOOKS_JSON=$(cat <<EOF
{
  "SessionStart": [
    {
      "hooks": [{"type": "command", "command": "$INSTALL_DIR/scripts/bootstrap.sh"}]
    }
  ],
  "UserPromptSubmit": [
    {
      "hooks": [{"type": "command", "command": "$INSTALL_DIR/scripts/capture-prompt.sh"}]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "Write|Edit|MultiEdit|Bash",
      "hooks": [{"type": "command", "command": "$INSTALL_DIR/scripts/observe.sh"}]
    }
  ],
  "Stop": [
    {
      "hooks": [{"type": "command", "command": "$INSTALL_DIR/scripts/pause-summary.sh"}]
    }
  ]
}
EOF
)

  if [ ! -f "$GLOBAL_SETTINGS" ]; then
    # No existing settings — create with hooks
    jq -n --argjson hooks "$HOOKS_JSON" '{hooks: $hooks}' > "$GLOBAL_SETTINGS"
    echo "✓ Created ~/.claude/settings.json with global hooks"
  elif jq -e '.hooks' "$GLOBAL_SETTINGS" > /dev/null 2>&1; then
    echo "⚠ ~/.claude/settings.json already has hooks — skipping global hook merge."
    echo "  To re-register: remove the \"hooks\" key from ~/.claude/settings.json and re-run setup."
  else
    # Merge hooks into existing settings
    local TMP
    TMP=$(mktemp)
    jq --argjson hooks "$HOOKS_JSON" '. + {hooks: $hooks}' "$GLOBAL_SETTINGS" > "$TMP" && mv "$TMP" "$GLOBAL_SETTINGS"
    echo "✓ Merged vibe-learn hooks into ~/.claude/settings.json"
  fi
  echo "✓ Slash commands installed to ~/.claude/commands/"
}

register_global_hooks

# --- PATH advisory ---
if [[ ":$PATH:" != *":$SHIM_DIR:"* ]]; then
  echo ""
  echo "NOTE: $SHIM_DIR is not in your PATH."
  echo "  Add this to your ~/.zshrc or ~/.bash_profile:"
  echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
  echo ""
  echo "  Or run install directly:"
  echo "    ~/.vibe-learn/scripts/install.sh /path/to/your/project"
else
  echo ""
  echo "vibe-learn is active globally — hooks fire in every Claude Code session."
  echo "For per-project overrides: vibe-learn install [/path/to/project]"
  echo ""
  echo "Obsidian integration:"
  echo "  /learn obsidian           — save learn note to your Obsidian vault"
  echo "  /learn obsidian:recall    — search vault for past learnings on a topic"
  echo "  /digest obsidian          — save session digest to your Obsidian vault"
  echo "  /digest obsidian:recall   — digest enriched with connections to past sessions"
fi
