#!/bin/bash
# doctor.sh — `vibe-learn doctor [target-dir]`: is vibe-learn installed and
# working here?
#
# Checks jq; that every file setup.sh installs is present and the hook scripts
# are executable; which assistants have vibe-learn hooks registered and
# whether the scripts they point at exist; that the global and project
# config.json parse and hold only known keys (config/defaults.json); the
# knowledge ledger; and the project's last session (event count, whether a
# Stop hook has run).
#
# Read-only. Prints one line per check (✓ ok, ! warning, ✗ failure, - not
# set up) and exits 1 when any check fails, so it works in CI.

set -uo pipefail

VIBE_LEARN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET_DIR=""
for arg in "$@"; do
  case "$arg" in
    --help|-h)
      sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "ERROR: Unknown doctor flag: $arg" >&2
      exit 1
      ;;
    *)
      if [ -n "$TARGET_DIR" ]; then
        echo "ERROR: doctor accepts at most one target directory." >&2
        exit 1
      fi
      TARGET_DIR="$arg"
      ;;
  esac
done
TARGET_DIR="${TARGET_DIR:-$(pwd)}"
ABS_DIR="$(CDPATH='' cd -- "$TARGET_DIR" 2>/dev/null && pwd)" || { echo "ERROR: no such directory: $TARGET_DIR" >&2; exit 1; }
TARGET_DIR="$ABS_DIR"

FAILURES=0
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
none() { printf '  - %s\n' "$*"; }
# Paths under $HOME print as ~/...
show() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

echo "vibe-learn doctor — $(show "$TARGET_DIR")"

# --- jq -------------------------------------------------------------------
echo ""
echo "jq"
if ! command -v jq >/dev/null 2>&1; then
  fail "jq not found; every hook needs it (brew install jq / apt-get install jq)"
  echo ""
  echo "1 problem found."
  exit 1
fi
JQ_VERSION="$(jq --version 2>/dev/null)"
JQ_VERSION="${JQ_VERSION#jq-}"
JQ_MAJOR="${JQ_VERSION%%.*}"
JQ_MINOR="${JQ_VERSION#*.}"
JQ_MINOR="${JQ_MINOR%%[!0-9]*}"
case "$JQ_MAJOR$JQ_MINOR" in
  ''|*[!0-9]*) warn "jq version not recognised: '$JQ_VERSION' (vibe-learn needs 1.6 or newer)" ;;
  *)
    if [ "$JQ_MAJOR" -gt 1 ] || { [ "$JQ_MAJOR" -eq 1 ] && [ "$JQ_MINOR" -ge 6 ]; }; then
      ok "jq $JQ_VERSION"
    else
      fail "jq $JQ_VERSION is too old; vibe-learn needs 1.6 or newer"
    fi
    ;;
esac

# --- install ----------------------------------------------------------------
# setup.sh's FILES list is the manifest: every file it installs must be here.
echo ""
echo "Install"
VERSION="$(cat "$VIBE_LEARN_DIR/VERSION" 2>/dev/null || echo unknown)"
if [ ! -f "$VIBE_LEARN_DIR/scripts/setup.sh" ]; then
  fail "$(show "$VIBE_LEARN_DIR/scripts/setup.sh") is missing; reinstall vibe-learn"
else
  MISSING=""
  N_FILES=0
  while IFS= read -r f; do
    N_FILES=$((N_FILES + 1))
    [ -f "$VIBE_LEARN_DIR/$f" ] || MISSING="$MISSING $f"
  done < <(sed -n '/^FILES=(/,/^)/s/^ *"\([^"]*\)".*/\1/p' "$VIBE_LEARN_DIR/scripts/setup.sh")
  for f in bootstrap capture-prompt observe pause-summary; do
    if [ -f "$VIBE_LEARN_DIR/scripts/$f.sh" ] && [ ! -x "$VIBE_LEARN_DIR/scripts/$f.sh" ]; then
      fail "scripts/$f.sh is not executable (chmod +x $(show "$VIBE_LEARN_DIR/scripts")/*.sh)"
    fi
  done
  if [ -n "$MISSING" ]; then
    for f in $MISSING; do fail "missing $f; reinstall vibe-learn"; done
  else
    ok "vibe-learn $VERSION at $(show "$VIBE_LEARN_DIR") ($N_FILES files)"
  fi
fi

# --- hooks ------------------------------------------------------------------
echo ""
echo "Hooks"

# Every script or shim path a host's hook file points at, one per line: quoted
# paths ending in a core hook script or the adapters' vibe-learn.sh shim, and
# install directories baked into a shim or set as VIBE_LEARN_INSTALL_DIR (as
# that directory's observe.sh). Works on JSON, TOML, JS, and shell alike.
hook_refs() {
  jq -Rr '
    (capture("[\"\\x27](?<p>[^\"\\x27]*(/scripts/|/hooks/vibe-learn/)(bootstrap|capture-prompt|observe|pause-summary)\\.sh)"; "g") | .p),
    (capture("[\"\\x27](?<p>[^\"\\x27]*hooks/vibe-learn\\.sh)"; "g") | .p),
    (capture("VIBE_LEARN_(INSTALL_)?DIR\"?\\s*[:=]\\s*[\"\\x27](?<d>[^\"\\x27]+)"; "g") | .d + "/scripts/observe.sh")
  ' "$1" 2>/dev/null | awk '!seen[$0]++'
}

# check_host <name> <file>... — report each file that registers vibe-learn.
REGISTERED=0
check_host() {
  local name="$1" f p found=0 missing refs seen=""
  shift
  for f in "$@"; do
    [ -f "$f" ] || continue
    # Run from $HOME, the global and project files are the same file.
    case "$seen" in *"|$f|"*) continue ;; esac
    seen="$seen|$f|"
    refs="$(hook_refs "$f")"
    [ -n "$refs" ] || continue
    found=1
    missing=""
    while IFS= read -r p; do
      case "$p" in *'$'*|*PLACEHOLDER*) continue ;; esac
      case "$p" in /*) ;; *) p="$TARGET_DIR/$p" ;; esac
      if [ ! -e "$p" ]; then
        missing="$p"
        break
      fi
      # A shim carries the install directory it was rendered with.
      case "$p" in
        */hooks/vibe-learn.sh)
          while IFS= read -r inner; do
            case "$inner" in *'$'*|*PLACEHOLDER*|*/hooks/vibe-learn.sh) continue ;; esac
            [ -e "$inner" ] || { missing="$inner"; break; }
          done < <(hook_refs "$p")
          ;;
      esac
      [ -z "$missing" ] || break
    done <<EOF
$refs
EOF
    if [ -n "$missing" ]; then
      fail "$name: $(show "$f") points at $(show "$missing"), which does not exist; re-run vibe-learn install or setup.sh"
    else
      ok "$name: hooks in $(show "$f")"
    fi
  done
  if [ "$found" -eq 1 ]; then
    REGISTERED=$((REGISTERED + 1))
    return 0
  fi
  return 1
}

CLAUDE_FILES=("$HOME/.claude/settings.json" "$TARGET_DIR/.claude/settings.json" "$TARGET_DIR/.claude/settings.local.json")
CLAUDE_PLUGIN=""
for f in "${CLAUDE_FILES[@]}"; do
  if [ -f "$f" ] && jq -e '(.enabledPlugins // {}) | to_entries | any((.key | startswith("vibe-learn@")) and .value == true)' "$f" >/dev/null 2>&1; then
    CLAUDE_PLUGIN="$f"
    break
  fi
done
CLAUDE_SETTINGS_HOOKS=false
check_host "Claude Code" "${CLAUDE_FILES[@]}" && CLAUDE_SETTINGS_HOOKS=true
if [ -n "$CLAUDE_PLUGIN" ]; then
  ok "Claude Code: vibe-learn plugin enabled in $(show "$CLAUDE_PLUGIN")"
  if [ "$CLAUDE_SETTINGS_HOOKS" = true ]; then
    warn "Claude Code: the plugin and settings hooks are both active, so every event is logged twice; re-run vibe-learn install to remove the settings hooks"
  else
    REGISTERED=$((REGISTERED + 1))
  fi
elif [ "$CLAUDE_SETTINGS_HOOKS" = false ]; then
  none "Claude Code: not set up"
fi
check_host "Codex" "$HOME/.codex/config.toml" "$TARGET_DIR/.codex/config.toml" || none "Codex: not set up"
check_host "OpenCode" "$HOME/.config/opencode/plugins/vibe-learn.js" "$TARGET_DIR/.opencode/plugins/vibe-learn.js" || none "OpenCode: not set up"
check_host "Grok Build" "${GROK_HOME:-$HOME/.grok}/hooks/vibe-learn.json" "$TARGET_DIR/.grok/hooks/vibe-learn.json" || none "Grok Build: not set up"
check_host "Cursor" "$HOME/.cursor/hooks.json" "$TARGET_DIR/.cursor/hooks.json" || none "Cursor: not set up"
check_host "GitHub Copilot CLI" "${COPILOT_HOME:-$HOME/.copilot}/hooks/vibe-learn.json" "$TARGET_DIR/.github/hooks/vibe-learn.json" || none "GitHub Copilot CLI: not set up"
if [ "$REGISTERED" -eq 0 ]; then
  fail "no assistant has vibe-learn hooks registered; run setup.sh, vibe-learn install, or install the plugin"
fi

# --- config -----------------------------------------------------------------
# config/defaults.json lists every key some script reads (tests/setup.bats).
echo ""
echo "Config"
DEFAULTS="$VIBE_LEARN_DIR/config/defaults.json"
KNOWN="$(jq -c '[del(._comment) | paths(scalars) | map(tostring) | join(".")]' "$DEFAULTS" 2>/dev/null)"
for f in "$HOME/.vibe-learn/config.json" "$TARGET_DIR/.vibe-learn/config.json"; do
  if [ ! -f "$f" ]; then
    none "$(show "$f"): none (defaults apply)"
  elif ! jq -e 'type == "object"' "$f" >/dev/null 2>&1; then
    fail "$(show "$f") is not a JSON object, so every script ignores it"
  elif [ -z "$KNOWN" ]; then
    warn "$(show "$f") parses, but $(show "$DEFAULTS") is missing, so its keys cannot be checked"
  else
    UNKNOWN="$(jq -r --argjson known "$KNOWN" '[del(._comment) | paths(scalars) | map(tostring) | join(".")] - $known | join(", ")' "$f")"
    if [ -n "$UNKNOWN" ]; then
      fail "$(show "$f"): nothing reads $UNKNOWN; remove it (known keys: $(show "$DEFAULTS"))"
    else
      ok "$(show "$f")"
    fi
  fi
done

# --- project ----------------------------------------------------------------
echo ""
echo "Project"
LOG_DIR="$TARGET_DIR/.vibe-learn"
if [ ! -d "$LOG_DIR" ]; then
  none "no .vibe-learn/ here yet; it appears after the first session in this project"
else
  LEDGER="$LOG_DIR/knowledge.json"
  if [ ! -f "$LEDGER" ]; then
    none "knowledge ledger: none yet (/quiz creates it)"
  elif N="$(jq -er 'select(type == "object" and (.concepts | type == "array")) | .concepts | length' "$LEDGER" 2>/dev/null)"; then
    ok "knowledge ledger: $N concept(s)"
  else
    fail "$(show "$LEDGER") is not a valid knowledge ledger; the knowledge helper refuses to write it (fix or remove it)"
  fi

  LOG="$LOG_DIR/session-log.jsonl"
  META="$LOG_DIR/session-meta.json"
  if [ ! -f "$LOG" ]; then
    none "session log: none yet"
  else
    SESSION="$(jq -r 'select(type == "object") | "\(.session_id // "unknown") (started \(.started_at // "unknown"))"' "$META" 2>/dev/null)"
    # One pass: counts by event, and lines that are not JSON objects.
    COUNTS="$(jq -nRr '[inputs | (try fromjson catch null) | if type == "object" then .event else "bad" end]
      | "\(map(select(. == "tool_use")) | length) \(map(select(. == "turn_end")) | length) \(map(select(. == "bad")) | length)"' "$LOG")"
    read -r TOOLS TURNS BAD <<EOF
$COUNTS
EOF
    TOOLS="${TOOLS:-0}" TURNS="${TURNS:-0}" BAD="${BAD:-0}"
    ok "last session ${SESSION:-unknown}: $TOOLS tool event(s), $TURNS finished turn(s)"
    if [ "$TOOLS" -gt 0 ] && [ "$TURNS" -eq 0 ]; then
      warn "no Stop hook has run this session; normal mid-turn, otherwise check that the Stop hook is registered"
    fi
    if [ "$BAD" -gt 0 ]; then
      warn "session log has $BAD line(s) that are not JSON objects; readers skip them"
    fi
  fi
fi

echo ""
if [ "$FAILURES" -eq 0 ]; then
  echo "All checks passed."
else
  echo "$FAILURES problem(s) found."
  exit 1
fi
