#!/usr/bin/env bash
# Install the vibe-deck gateway as a launchd agent (survives reboot).
#
# Prereqs:
#   - venv:   python3 -m venv ~/.vibe-deck/venv &&
#             ~/.vibe-deck/venv/bin/pip install -r deck/gateway/requirements.txt
#   - config: ~/.vibe-deck/env with at least GATEWAY_SECRET=...
#   - CLIs:   `claude` and `codex` signed in for this user
#
# Usage: deck/mac/install_gateway.sh [--uninstall]

set -euo pipefail

LABEL="com.vibedeck.gateway"
DECK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_PYTHON="$HOME/.vibe-deck/venv/bin/python"
PLIST_SRC="$DECK_DIR/mac/$LABEL.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"
GUI_DOMAIN="gui/$(id -u)"

if [[ "${1:-}" == "--uninstall" ]]; then
  launchctl bootout "$GUI_DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$PLIST_DST"
  echo "uninstalled $LABEL"
  exit 0
fi

[[ -x "$VENV_PYTHON" ]] || { echo "venv missing: $VENV_PYTHON (see header)"; exit 1; }
grep -q "GATEWAY_SECRET=" "$HOME/.vibe-deck/env" 2>/dev/null \
  || { echo "GATEWAY_SECRET not set in ~/.vibe-deck/env"; exit 1; }

# claude/codex live in user-specific bins; bake their dirs into PATH so
# launchd (which has a minimal environment) can spawn them.
CLI_PATH="$(dirname "$(command -v claude)")":"$(dirname "$(command -v codex)")"

mkdir -p "$HOME/Library/LaunchAgents"
sed -e "s|__VENV_PYTHON__|$VENV_PYTHON|g" \
    -e "s|__DECK_DIR__|$DECK_DIR|g" \
    -e "s|__CLI_PATH__|$CLI_PATH|g" \
    "$PLIST_SRC" > "$PLIST_DST"

launchctl bootout "$GUI_DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootstrap "$GUI_DOMAIN" "$PLIST_DST"
launchctl kickstart -k "$GUI_DOMAIN/$LABEL"

echo "installed $LABEL"
echo "  logs:   tail -f /tmp/vibe-deck.err.log"
echo "  health: curl -H \"x-gateway-secret: \$(grep GATEWAY_SECRET ~/.vibe-deck/env | cut -d= -f2)\" http://127.0.0.1:8756/health"
