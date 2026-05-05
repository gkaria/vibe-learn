#!/bin/bash
# setup.sh — curl-installable setup for vibe-learn
# Installs vibe-learn to ~/.vibe-learn/ and creates a CLI shim.
#
# Usage (from GitHub):
#   curl -fsSL https://raw.githubusercontent.com/gkaria/vibe-learn/main/scripts/setup.sh | bash
#
# Usage (local testing, no network):
#   bash /path/to/vibe-learn/scripts/setup.sh --local
#
# Assistant selection:
#   --assistant=claude-code   Configure Claude Code only
#   --assistant=codex         Configure Codex CLI only
#   --assistant=all           Configure all detected assistants
#   (default: auto-detect based on installed binaries / config dirs)

set -euo pipefail

VIBE_LEARN_VERSION="0.3.0" # x-release-please-version
INSTALL_DIR="$HOME/.vibe-learn"
SHIM_DIR="$HOME/.local/bin"
SHIM_PATH="$SHIM_DIR/vibe-learn"
GITHUB_RAW="https://raw.githubusercontent.com/gkaria/vibe-learn/main"

LOCAL_MODE=false
ASSISTANT_FLAG=""

for arg in "$@"; do
  case "$arg" in
    --local)
      LOCAL_MODE=true
      ;;
    --assistant=*)
      ASSISTANT_FLAG="${arg#--assistant=}"
      ;;
  esac
done

if [ "$LOCAL_MODE" = true ]; then
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
  "config/defaults.json"
  "config/obsidian-defaults.json"
  "adapters/claude-code/hooks.json"
  "adapters/claude-code/commands/learn.md"
  "adapters/claude-code/commands/digest.md"
  "adapters/claude-code/install.sh"
  "adapters/codex/hooks.toml"
  "adapters/codex/prompts/learn.md"
  "adapters/codex/prompts/digest.md"
  "adapters/codex/skills/vibe-learn/SKILL.md"
  "adapters/codex/install.sh"
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
chmod +x "$INSTALL_DIR/adapters/claude-code/install.sh"
chmod +x "$INSTALL_DIR/adapters/codex/install.sh"

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

# --- Detect which assistants to configure ---
detect_assistants() {
  local detected=()
  if command -v claude &>/dev/null || [ -d "$HOME/.claude" ]; then
    detected+=("claude-code")
  fi
  if command -v codex &>/dev/null || [ -d "$HOME/.codex" ]; then
    detected+=("codex")
  fi
  if [ ${#detected[@]} -eq 0 ]; then
    detected+=("claude-code")
  fi
  echo "${detected[@]}"
}

assistant_list_contains() {
  local needle="$1"
  shift
  local assistant
  for assistant in "$@"; do
    if [ "$assistant" = "$needle" ]; then
      return 0
    fi
  done
  return 1
}

join_assistants() {
  local result=""
  local assistant
  for assistant in "$@"; do
    if [ -z "$result" ]; then
      result="$assistant"
    else
      result="$result, $assistant"
    fi
  done
  echo "$result"
}

if [ -n "$ASSISTANT_FLAG" ]; then
  case "$ASSISTANT_FLAG" in
    all)
      read -ra ASSISTANTS_TO_CONFIGURE <<< "$(detect_assistants)"
      ;;
    claude-code|codex)
      ASSISTANTS_TO_CONFIGURE=("$ASSISTANT_FLAG")
      ;;
    *)
      echo "ERROR: Unknown assistant '$ASSISTANT_FLAG'. Supported: claude-code, codex, all" >&2
      exit 1
      ;;
  esac
else
  read -ra ASSISTANTS_TO_CONFIGURE <<< "$(detect_assistants)"
fi

# --- Register hooks for each detected assistant ---
for ASSISTANT in "${ASSISTANTS_TO_CONFIGURE[@]}"; do
  ADAPTER_SCRIPT="$INSTALL_DIR/adapters/$ASSISTANT/install.sh"
  if [ ! -f "$ADAPTER_SCRIPT" ]; then
    echo "⚠ No adapter found for '$ASSISTANT' — skipping."
    continue
  fi
  echo "Configuring $ASSISTANT..."
  bash "$ADAPTER_SCRIPT" --global "$INSTALL_DIR"
done

echo ""
CONFIGURED="$(join_assistants "${ASSISTANTS_TO_CONFIGURE[@]}")"
echo "vibe-learn is active globally for: $CONFIGURED"

if assistant_list_contains "claude-code" "${ASSISTANTS_TO_CONFIGURE[@]}"; then
  echo ""
  echo "Claude Code:"
  echo "  /learn                      — explain what just happened, or ask a specific question"
  echo "  /digest                     — full session learning report"
fi

if assistant_list_contains "codex" "${ASSISTANTS_TO_CONFIGURE[@]}"; then
  echo ""
  echo "Codex:"
  echo "  Codex does not support custom /learn slash commands."
  echo "  Use the global skill: \"Use vibe-learn to learn what happened.\""
  echo "  Prompt fallbacks are installed in ~/.codex/prompts/."
fi

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
  echo "For per-project overrides: vibe-learn install [/path/to/project]"
  echo ""
  echo "Obsidian integration:"
  echo "  /learn obsidian           — save learn note to your Obsidian vault"
  echo "  /learn obsidian:recall    — search vault for past learnings on a topic"
  echo "  /digest obsidian          — save session digest to your Obsidian vault"
  echo "  /digest obsidian:recall   — digest enriched with connections to past sessions"
fi
