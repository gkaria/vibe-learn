#!/bin/bash
# bootstrap.sh — SessionStart hook
# Initialises the .vibe-learn/ directory, rotates previous logs, starts the
# finished session's briefing in the background, and injects prior session
# context if available.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=identity.sh
if ! . "$SCRIPT_DIR/identity.sh" 2>/dev/null; then
  # Installs that copy hook scripts one by one may lack the helper.
  VL_SEP=$'\x1f'
  vl_resolve_harness() { printf '%s' "${VIBE_LEARN_HARNESS:-${1:-unknown}}"; }
  vl_host_config() { :; }
  vl_harness_version() { :; }
fi

# Detached work after a rotation (started below, never by a host): the
# finished session's health rows, then its briefing, both from the snapshot
# bootstrap.sh claimed. Neither fits in SessionStart's 5 s on a long log.
if [ "${1:-}" = "--after-rotation" ]; then
  SNAP="$2" CWD="$3" HEALTH_ENABLED="$4" HEALTH_GLOBAL="$5"
  trap '' HUP
  if [ "$HEALTH_ENABLED" != "false" ] && [ -f "$SCRIPT_DIR/health.sh" ]; then
    ROWS=$(bash "$SCRIPT_DIR/health.sh" "$SNAP" "$CWD")
    if [ -n "$ROWS" ]; then
      printf '%s\n' "$ROWS" >> "$CWD/.vibe-learn/health.jsonl"
      if [ "$HEALTH_GLOBAL" != "false" ] && mkdir -p "$HOME/.vibe-learn"; then
        printf '%s\n' "$ROWS" | jq -c --arg project "$(basename "$CWD")" '. + {project: $project}' >> "$HOME/.vibe-learn/health.jsonl"
      fi
    fi
  fi
  if [ -f "$SCRIPT_DIR/briefing.sh" ]; then
    bash "$SCRIPT_DIR/briefing.sh" "$CWD" --snapshot "$SNAP" --lock-wait 1800 >/dev/null
  fi
  rm -rf "$SNAP"
  exit 0
fi

# Read stdin JSON
INPUT=$(cat)

# Extract cwd and session_id (jq required). Accept Claude snake_case and Grok camelCase.
CWD=$(echo "$INPUT" | jq -r '.cwd // .workspaceRoot // empty' 2>/dev/null || true)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // .sessionId // empty' 2>/dev/null || true)
# Grok hook-runner env only — GROK_SESSION_ID can leak into agent shells.
if [ -n "${GROK_HOOK_EVENT:-}" ]; then
  if [ -z "$CWD" ]; then
    CWD="${GROK_WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-}}"
  fi
  if [ -z "$SESSION_ID" ]; then
    SESSION_ID="${GROK_SESSION_ID:-}"
  fi
fi

# Fall back gracefully if cwd is missing
if [ -z "$CWD" ]; then
  exit 0
fi

LOG_DIR="$CWD/.vibe-learn"
SESSION_LOG="$LOG_DIR/session-log.jsonl"
PREV_LOG="$LOG_DIR/session-log.prev.jsonl"
META_FILE="$LOG_DIR/session-meta.json"
PREV_META="$LOG_DIR/session-meta.prev.json"
PAUSE_SUMMARY="$LOG_DIR/pause-summary.txt"

# Create the .vibe-learn directory
mkdir -p "$LOG_DIR"

# Health switches from ~/.vibe-learn/config.json, overridden by the project's
# .vibe-learn/config.json. Both default to on, and stay on if either file is
# malformed.
GLOBAL_HOME="$HOME/.vibe-learn"
CONFIG_FILES=()
for f in "$GLOBAL_HOME/config.json" "$LOG_DIR/config.json"; do
  [ -f "$f" ] && CONFIG_FILES+=("$f")
done
HEALTH_ENABLED=true
HEALTH_GLOBAL=true
if [ "${#CONFIG_FILES[@]}" -gt 0 ]; then
  VL_READ_1=$(jq -rn --arg sep "$VL_SEP" '
  [inputs | objects | .health | objects] | add // {}
  | (if .enabled == false then "false" else "true" end) + $sep
    + (if .global_log == false then "false" else "true" end)' "${CONFIG_FILES[@]}" 2>/dev/null || printf 'true%strue' "$VL_SEP")
IFS="$VL_SEP" read -r HEALTH_ENABLED HEALTH_GLOBAL <<EOF
$VL_READ_1
EOF
fi

# Resuming the session that owns the current log (claude --continue, /compact)
# fires SessionStart again with the same id. Keep its log and
# metadata, and skip the prior-session summary the assistant already has.
OLD_META="$(cat "$META_FILE" 2>/dev/null || true)"
if [ -n "$SESSION_ID" ] && [ "$SESSION_ID" != "unknown" ] \
  && [ "$(printf '%s' "$OLD_META" | jq -r '.session_id // empty' 2>/dev/null | head -n 1)" = "$SESSION_ID" ]; then
  exit 0
fi

# Get current timestamp (ISO 8601)
STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Identity: which assistant, version, model, and effort this session runs on.
VL_READ_2=$(printf '%s' "$INPUT" | jq -r --arg sep "$VL_SEP" '
  def str: if type == "string" then . else "" end;
  [ (.harness | str),
    (.harness_version | str),
    ((.model_id // .model) | str),
    ((.effort | if type == "object" then .level else . end) | str),
    ((.transcript_path // .transcriptPath) | str),
    ((.workspaceRoot // .cwd) | str)
  ] | join($sep)' 2>/dev/null)
IFS="$VL_SEP" read -r P_HARNESS P_VERSION P_MODEL P_EFFORT P_TRANSCRIPT P_ROOT <<EOF
$VL_READ_2
EOF
HARNESS=$(vl_resolve_harness "${P_HARNESS:-}" "${P_TRANSCRIPT:-}")
HARNESS_VERSION="${P_VERSION:-}"
[ -n "$HARNESS_VERSION" ] || HARNESS_VERSION=$(vl_harness_version "$HARNESS" "${P_TRANSCRIPT:-}")
VL_READ_3=$(vl_host_config "$HARNESS" "${P_TRANSCRIPT:-}" "${P_ROOT:-$CWD}" "${SESSION_ID:-}")
IFS="$VL_SEP" read -r H_MODEL H_EFFORT <<EOF
$VL_READ_3
EOF
# The payload describes the session starting now; a resumed transcript may
# still end with the previous model.
MODEL="${P_MODEL:-${H_MODEL:-}}"
EFFORT="${P_EFFORT:-${H_EFFORT:-}}"

GIT_HEAD=""
GIT_DIRTY=""
if GIT_HEAD=$(git -C "$CWD" rev-parse --short HEAD 2>/dev/null); then
  if [ -n "$(git -C "$CWD" --no-optional-locks status --porcelain 2>/dev/null | head -n 1)" ]; then
    GIT_DIRTY=true
  else
    GIT_DIRTY=false
  fi
else
  GIT_HEAD=""
fi

# Fresh session metadata, written once the old log is claimed below.
NEW_META=$(jq -n \
  --arg session_id "${SESSION_ID:-unknown}" \
  --arg started_at "$STARTED_AT" \
  --arg harness "$HARNESS" \
  --arg harness_version "$HARNESS_VERSION" \
  --arg model "$MODEL" \
  --arg effort "$EFFORT" \
  --arg transcript_path "${P_TRANSCRIPT:-}" \
  --arg git_head "$GIT_HEAD" \
  --arg git_dirty "$GIT_DIRTY" '
  def nonempty: if . == "" then null else . end;
  {
    session_id: $session_id,
    started_at: $started_at,
    harness: $harness,
    harness_version: ($harness_version | nonempty),
    model: ($model | nonempty),
    effort: ($effort | nonempty),
    transcript_path: ($transcript_path | nonempty),
    git_head: ($git_head | nonempty),
    git_dirty: (if $git_dirty == "" then null else $git_dirty == "true" end),
    event_count: 0,
    current_turn: 0
  }')

# Rotate: claim the finished session's log with one atomic mv into a private
# snapshot, so two SessionStarts at once cannot both rotate it, then write the
# new meta at once so the live log and meta stay a pair. The snapshot gets the
# finished session's meta (read before anything changed), pause summary and
# the file naming its session, the ledger, and the work tree's diff: from now
# on the tree, the ledger and the .prev files belong to the next session. The
# .prev pair is kept for recap. Snapshots left by killed runs are swept here
# once they are a day old.
PENDING_DIR="$LOG_DIR/briefing/.pending"
ROTATED=false
SNAP=""
if [ -f "$SESSION_LOG" ]; then
  find "$PENDING_DIR" -mindepth 1 -maxdepth 1 -mmin +1440 -exec rm -rf {} + 2>/dev/null || true
  SNAP="$(mkdir -p "$PENDING_DIR" 2>/dev/null && mktemp -d "$PENDING_DIR/XXXXXX" 2>/dev/null)" || SNAP=""
  if [ -n "$SNAP" ] && mv "$SESSION_LOG" "$SNAP/session-log.jsonl" 2>/dev/null; then
    ROTATED=true
  else
    [ -n "$SNAP" ] && rm -rf "$SNAP"
    SNAP=""
    # No snapshot possible (unwritable briefing dir): rotate without one.
    mv "$SESSION_LOG" "$PREV_LOG" 2>/dev/null && ROTATED=true
  fi
fi
printf '%s\n' "$NEW_META" > "$META_FILE.tmp.$$" && mv "$META_FILE.tmp.$$" "$META_FILE"

if [ "$ROTATED" = true ]; then
  rm -f "$PREV_META"
  if [ -n "$OLD_META" ]; then
    printf '%s\n' "$OLD_META" > "$PREV_META"
    [ -n "$SNAP" ] && cp "$PREV_META" "$SNAP/session-meta.json"
  fi
fi

if [ -n "$SNAP" ]; then
  cp "$SNAP/session-log.jsonl" "$PREV_LOG.tmp.$$" 2>/dev/null && mv "$PREV_LOG.tmp.$$" "$PREV_LOG"
  for f in pause-summary.txt pause-summary.session knowledge.json; do
    [ -f "$LOG_DIR/$f" ] && cp "$LOG_DIR/$f" "$SNAP/$f" 2>/dev/null
  done
  # The diff is capped as briefing.sh caps it; head closing the pipe stops git
  # early. No external diff or textconv driver runs, diff.autoRefreshIndex=false
  # skips re-reading every stat-dirty file before the first line (300 ms ->
  # 60 ms with 20k dirty files in a 100k-file tree), and a 2 s deadline bounds
  # what is left (a huge dirty file is read whole before any output): past it,
  # or on any error, the diff stays empty. Never the live tree later.
  mkdir -p "$SNAP/repo"
  # SIGKILL follows (or SIGALRM is reset to its default) because a caller may
  # leave SIGTERM ignored, and an ignored signal stays ignored across exec.
  DEADLINE=()
  if command -v timeout >/dev/null 2>&1; then
    DEADLINE=(timeout -k 1 2)
  elif command -v perl >/dev/null 2>&1; then
    DEADLINE=(perl -e '$SIG{ALRM} = "DEFAULT"; alarm shift; exec @ARGV' 2)
  fi
  "${DEADLINE[@]}" git -C "$CWD" -c diff.autoRefreshIndex=false --no-optional-locks \
    diff --no-ext-diff --no-textconv --unified=3 -- . ':(exclude).vibe-learn' 2>/dev/null \
    | head -c 12000 > "$SNAP/repo/diff.patch"
  case "${PIPESTATUS[0]}" in
    0|141) ;;          # done, or stopped by head at the cap
    *) : > "$SNAP/repo/diff.patch" ;;
  esac

  # Health rows and the briefing run fully detached: no fd may keep the
  # host's pipe to this hook open (3-9 are closed too: bats and some hosts
  # pass extra pipes), and the hook returns at once. setsid gives the run its
  # own session; macOS has no setsid, so the fallback subshell backgrounds it
  # and exits, reparenting it to init, and the run ignores SIGHUP. Errors go
  # to briefing/rotation.log. The run removes the snapshot when it is done.
  if [ -s "$SNAP/session-log.jsonl" ]; then
    ROTATION_LOG="$LOG_DIR/briefing/rotation.log"
    if command -v setsid >/dev/null 2>&1; then
      setsid bash "$SCRIPT_DIR/bootstrap.sh" --after-rotation "$SNAP" "$CWD" "$HEALTH_ENABLED" "$HEALTH_GLOBAL" \
        </dev/null >/dev/null 2>>"$ROTATION_LOG" 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- &
    else
      ( bash "$SCRIPT_DIR/bootstrap.sh" --after-rotation "$SNAP" "$CWD" "$HEALTH_ENABLED" "$HEALTH_GLOBAL" \
          </dev/null >/dev/null 2>>"$ROTATION_LOG" 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- & )
    fi
  else
    rm -rf "$SNAP"
  fi
fi

# Inject the prior pause summary only when it belongs to the session that
# just ended (pause-summary.session matches its meta). A session that wrote
# none (chat only, or no Stop hook) leaves an older summary in place, which
# must not be offered as the prior session.
if [ -f "$PAUSE_SUMMARY" ] && [ -f "$PREV_META" ] \
  && [ "$(cat "$LOG_DIR/pause-summary.session" 2>/dev/null)" = "$(jq -c '[.session_id, .started_at]' "$PREV_META" 2>/dev/null)" ]; then
  tr '\n' ' ' < "$PAUSE_SUMMARY" \
    | jq -Rsc '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:("Prior session summary:\n" + .)}}'
fi
exit 0
