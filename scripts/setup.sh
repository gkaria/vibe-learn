#!/bin/bash
# setup.sh — curl-installable setup for vibe-learn
# Installs vibe-learn to ~/.vibe-learn/ and creates a CLI shim.
#
# Usage (from GitHub):
#   curl -fsSL https://raw.githubusercontent.com/gaurangkaria/vibe-learn/main/scripts/setup.sh | bash
#
# Usage (local testing, no network):
#   bash /path/to/vibe-learn/scripts/setup.sh --local

set -euo pipefail

VIBE_LEARN_VERSION="0.1.0"
INSTALL_DIR="$HOME/.vibe-learn"
SHIM_DIR="$HOME/.local/bin"
SHIM_PATH="$SHIM_DIR/vibe-learn"
GITHUB_RAW="https://raw.githubusercontent.com/gaurangkaria/vibe-learn/main"

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
)

# --- Download or copy files ---
for FILE in "${FILES[@]}"; do
  DEST="$INSTALL_DIR/$FILE"
  mkdir -p "$(dirname "$DEST")"

  if [ "$LOCAL_MODE" = true ]; then
    cp "$LOCAL_SOURCE/$FILE" "$DEST"
  else
    curl -fsSL "$GITHUB_RAW/$FILE" -o "$DEST"
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
exec "$HOME/.vibe-learn/scripts/install.sh" "$@"
EOF
chmod +x "$SHIM_PATH"

echo "✓ vibe-learn $VIBE_LEARN_VERSION installed to $INSTALL_DIR"
echo "✓ CLI shim created at $SHIM_PATH"

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
  echo "Run inside any project to activate vibe-learn:"
  echo "  vibe-learn install"
  echo "  # or: vibe-learn install /path/to/project"
fi
