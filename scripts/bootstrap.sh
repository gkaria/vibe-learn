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
if [ -n "$SESSION_ID" ] && [ "$SESSION_ID" != "unknown" ] \
  && [ "$(jq -r '.session_id // empty' "$META_FILE" 2>/dev/null)" = "$SESSION_ID" ]; then
  exit 0
fi

# Rotate previous session log (keep one backup), first saving its health rows.
# The old session-meta.json still describes that session at this point.
ROTATED=false
if [ -f "$SESSION_LOG" ]; then
  if [ "$HEALTH_ENABLED" != "false" ]; then
    ROWS=$(bash "$SCRIPT_DIR/health.sh" "$LOG_DIR" 2>/dev/null || true)
    if [ -n "$ROWS" ]; then
      printf '%s\n' "$ROWS" 2>/dev/null >> "$LOG_DIR/health.jsonl" || true
      if [ "$HEALTH_GLOBAL" != "false" ] && mkdir -p "$GLOBAL_HOME" 2>/dev/null; then
        printf '%s\n' "$ROWS" \
          | jq -c --arg project "$(basename "$CWD")" '. + {project: $project}' \
            2>/dev/null >> "$GLOBAL_HOME/health.jsonl" || true
      fi
    fi
  fi
  mv "$SESSION_LOG" "$PREV_LOG"
  # Snapshot the finished session's metadata too: it is overwritten below,
  # and the rotation briefing needs that session's id and start time.
  rm -f "$PREV_META"
  [ -f "$META_FILE" ] && cp "$META_FILE" "$PREV_META" 2>/dev/null
  ROTATED=true
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
  if [ -n "$(git -C "$CWD" status --porcelain 2>/dev/null | head -n 1)" ]; then
    GIT_DIRTY=true
  else
    GIT_DIRTY=false
  fi
else
  GIT_HEAD=""
fi

# Write fresh session metadata
jq -n \
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
  }' > "$META_FILE"

# Build the finished session's briefing once, in a fully detached process: no
# fd may keep the host's pipe to this hook open, and the hook returns at once.
# The run reads its own copy of the finished session (log, meta, and the pause
# summary with the file naming its session, which briefing.sh checks) under
# briefing/.pending/, because the next rotation overwrites the .prev files
# while this run may still be waiting up to 60 s on the briefing lock. The
# wrapper removes the copy when briefing.sh exits, whatever its status; copies
# left by killed runs are swept here once they are a day old. setsid gives the
# run its own session; macOS has no setsid, so the fallback subshell
# backgrounds it and exits, reparenting it to init.
BRIEFING="$SCRIPT_DIR/briefing.sh"
PENDING_DIR="$LOG_DIR/briefing/.pending"
if [ "$ROTATED" = true ] && [ -s "$PREV_LOG" ] && [ -f "$BRIEFING" ]; then
  find "$PENDING_DIR" -mindepth 1 -maxdepth 1 -mmin +1440 -exec rm -rf {} + 2>/dev/null || true
  SNAP="$(mkdir -p "$PENDING_DIR" && mktemp -d "$PENDING_DIR/XXXXXX" 2>/dev/null)" || SNAP=""
  if [ -n "$SNAP" ] && cp "$PREV_LOG" "$SNAP/session-log.jsonl" 2>/dev/null; then
    [ -f "$PREV_META" ] && cp "$PREV_META" "$SNAP/session-meta.json" 2>/dev/null
    [ -f "$PAUSE_SUMMARY" ] && cp "$PAUSE_SUMMARY" "$SNAP/pause-summary.txt" 2>/dev/null
    [ -f "$LOG_DIR/pause-summary.session" ] && cp "$LOG_DIR/pause-summary.session" "$SNAP/" 2>/dev/null
    # From now on the work tree belongs to the next session, so the diff is
    # taken here, capped as briefing.sh caps it; head closing the pipe stops
    # git early. diff.autoRefreshIndex=false skips re-reading every
    # stat-dirty file before the first line is printed (300 ms -> 60 ms with
    # 20k dirty files in a 100k-file tree). repo/ holds what the briefing
    # reads from the work tree.
    mkdir -p "$SNAP/repo"
    git -C "$CWD" -c diff.autoRefreshIndex=false --no-optional-locks \
      diff --unified=3 -- . ':(exclude).vibe-learn' 2>/dev/null \
      | head -c 12000 > "$SNAP/repo/diff.patch"
    RUN='bash "$1" "$2" --log "$3/session-log.jsonl" --meta "$3/session-meta.json" --diff "$3/repo/diff.patch" --lock-wait 60; rm -rf "$3"'
    if command -v setsid >/dev/null 2>&1; then
      setsid bash -c "$RUN" _ "$BRIEFING" "$CWD" "$SNAP" </dev/null >/dev/null 2>&1 &
    else
      ( bash -c "$RUN" _ "$BRIEFING" "$CWD" "$SNAP" </dev/null >/dev/null 2>&1 & )
    fi
  else
    [ -n "$SNAP" ] && rm -rf "$SNAP"
  fi
fi

# If a prior pause summary exists, inject it as context for Claude
if [ -f "$PAUSE_SUMMARY" ]; then
  tr '\n' ' ' < "$PAUSE_SUMMARY" \
    | jq -Rsc '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:("Prior session summary:\n" + .)}}'
else
  exit 0
fi
