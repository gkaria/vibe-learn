#!/usr/bin/env bash
# Install the cardputer-mcp HTTP bridge as an always-on launchd agent.
#
# This is the daemon that owns the BLE link and serves streamable-http on
# 127.0.0.1:9000 — reached by local Claude Code (loopback) and by cloud
# agents (through the MCP tunnel in ../tunnel). Idempotent; no sudo.
#
# Two-phase, like install_launchd.sh: first run writes a stub env file and
# exits so you can paste your tokens; second run renders + bootstraps.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/.." && pwd)"
VENV_PYTHON="${REPO}/mcp/.venv/bin/python"
SERVER_PY="${REPO}/mcp/server.py"
PLIST_SRC="${HERE}/com.cardputer.bridge.plist"
PLIST_DST="${HOME}/Library/LaunchAgents/com.cardputer.bridge.plist"
LABEL="com.cardputer.bridge"
CONFIG_DIR="${HOME}/.config/cardputer-bridge"
ENV_PATH="${CONFIG_DIR}/env"

if [[ ! -x "${VENV_PYTHON}" ]]; then
  echo "Bridge venv not found at ${VENV_PYTHON}"
  echo "Set it up first:"
  echo "  cd ${REPO}/mcp && python3 -m venv .venv && \\"
  echo "    .venv/bin/pip install -r requirements.txt"
  exit 1
fi

# 1) Ensure the env file exists; if not, write a stub and exit so secrets
#    are filled in before launchd starts the daemon.
if [[ ! -f "${ENV_PATH}" ]]; then
  mkdir -p "${CONFIG_DIR}"
  cat > "${ENV_PATH}" <<'ENVSTUB'
# cardputer-mcp bridge daemon config (user-only; never committed).
# CARDPUTER_TOKENS maps bearer token -> agent label shown on the device
# banner. Use a distinct token per agent class. Pick long random tokens.
CARDPUTER_TOKENS=REPLACE_LOCAL_TOKEN=claude-code,REPLACE_CLOUD_TOKEN=managed-agent
# The tunnel domain from the Console (so the daemon allow-lists the Host
# header tunneled requests arrive with). Leave blank if you only use the
# local loopback path.
CARDPUTER_TUNNEL_DOMAIN=
# Port the daemon listens on (loopback). Match ../tunnel/config/mcp-proxy.yaml.
CARDPUTER_HTTP_PORT=9000
ENVSTUB
  chmod 600 "${ENV_PATH}"
  echo
  echo "Wrote stub env to ${ENV_PATH}"
  echo "Edit it (set real random tokens + tunnel domain), then re-run this script."
  exit 0
fi

if grep -q "REPLACE_" "${ENV_PATH}"; then
  echo "Refusing to install: ${ENV_PATH} still has REPLACE_ placeholders."
  echo "Edit it first (set strong random tokens)."
  exit 1
fi

# 2) Load the env values.
set -a
# shellcheck disable=SC1090
source "${ENV_PATH}"
set +a
: "${CARDPUTER_TOKENS:?CARDPUTER_TOKENS must be set in ${ENV_PATH}}"
CARDPUTER_HTTP_PORT="${CARDPUTER_HTTP_PORT:-9000}"
CARDPUTER_TUNNEL_DOMAIN="${CARDPUTER_TUNNEL_DOMAIN:-}"

# 3) Render the plist with real paths + values. Use a sed delimiter that
#    won't collide with the comma/equals in token strings.
mkdir -p "$(dirname "${PLIST_DST}")"
sed \
  -e "s#__VENV_PYTHON__#${VENV_PYTHON}#g" \
  -e "s#__SERVER_PY__#${SERVER_PY}#g" \
  -e "s#__CARDPUTER_HTTP_PORT__#${CARDPUTER_HTTP_PORT}#g" \
  -e "s#__CARDPUTER_TOKENS__#${CARDPUTER_TOKENS}#g" \
  -e "s#__CARDPUTER_TUNNEL_DOMAIN__#${CARDPUTER_TUNNEL_DOMAIN}#g" \
  "${PLIST_SRC}" > "${PLIST_DST}"
chmod 600 "${PLIST_DST}"  # carries tokens

# 4) (Re)bootstrap.
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "${PLIST_DST}"
launchctl kickstart -k "gui/$(id -u)/${LABEL}"

LOCAL_TOKEN="$(printf '%s' "${CARDPUTER_TOKENS}" | cut -d, -f1 | cut -d= -f1)"

echo
echo "Installed launchd agent: ${LABEL}"
echo "  plist:  ${PLIST_DST}  (user-only; holds your tokens)"
echo "  daemon: ${VENV_PYTHON} ${SERVER_PY}  (CARDPUTER_HTTP=1, port ${CARDPUTER_HTTP_PORT})"
echo "  logs:   tail -f /tmp/cardputer-bridge.out.log /tmp/cardputer-bridge.err.log"
echo
echo "macOS Bluetooth permission: the FIRST BLE scan triggers a one-time"
echo "TCC prompt — approve Bluetooth for the daemon (System Settings >"
echo "Privacy & Security > Bluetooth). Until then scans fail."
echo
echo "Point LOCAL Claude Code at the same daemon (unified gate):"
echo "  claude mcp add --transport http cardputer \\"
echo "    http://127.0.0.1:${CARDPUTER_HTTP_PORT}/mcp \\"
echo "    --header \"Authorization: Bearer ${LOCAL_TOKEN}\""
echo
echo "Cloud agents: see ${REPO}/tunnel/README.md"
echo
echo "Stop / uninstall:"
echo "  launchctl bootout gui/\$(id -u)/${LABEL} && rm ${PLIST_DST}"
