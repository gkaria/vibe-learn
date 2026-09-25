#!/bin/bash
# bootstrap.sh — SessionStart hook
# Initialises the .vibe-learn/ directory, rotates previous logs,
# and injects prior session context if available.

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
  IFS="$VL_SEP" read -r HEALTH_ENABLED HEALTH_GLOBAL <<EOF
$(jq -rn --arg sep "$VL_SEP" '
  [inputs | objects | .health | objects] | add // {}
  | (if .enabled == false then "false" else "true" end) + $sep
    + (if .global_log == false then "false" else "true" end)' "${CONFIG_FILES[@]}" 2>/dev/null || printf 'true%strue' "$VL_SEP")
EOF
fi

# Rotate previous session log (keep one backup), first saving its health rows.
# The old session-meta.json still describes that session at this point.
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
fi

# Get current timestamp (ISO 8601)
STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Identity: which assistant, version, model, and effort this session runs on.
IFS="$VL_SEP" read -r P_HARNESS P_VERSION P_MODEL P_EFFORT P_TRANSCRIPT P_ROOT <<EOF
$(printf '%s' "$INPUT" | jq -r --arg sep "$VL_SEP" '
  def str: if type == "string" then . else "" end;
  [ (.harness | str),
    (.harness_version | str),
    ((.model_id // .model) | str),
    ((.effort | if type == "object" then .level else . end) | str),
    ((.transcript_path // .transcriptPath) | str),
    ((.workspaceRoot // .cwd) | str)
  ] | join($sep)' 2>/dev/null)
EOF
HARNESS=$(vl_resolve_harness "${P_HARNESS:-}" "${P_TRANSCRIPT:-}")
HARNESS_VERSION="${P_VERSION:-}"
[ -n "$HARNESS_VERSION" ] || HARNESS_VERSION=$(vl_harness_version "$HARNESS" "${P_TRANSCRIPT:-}")
IFS="$VL_SEP" read -r H_MODEL H_EFFORT <<EOF
$(vl_host_config "$HARNESS" "${P_TRANSCRIPT:-}" "${P_ROOT:-$CWD}" "${SESSION_ID:-}")
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
    current_turn: 0,
    config: {log_dir: ".vibe-learn"}
  }' > "$META_FILE"

# If a prior pause summary exists, inject it as context for Claude
if [ -f "$PAUSE_SUMMARY" ]; then
  SUMMARY_CONTENT=$(cat "$PAUSE_SUMMARY")
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Prior session summary:\\n%s"}}\n' \
    "$(echo "$SUMMARY_CONTENT" | sed 's/"/\\"/g' | tr '\n' ' ')"
else
  exit 0
fi
