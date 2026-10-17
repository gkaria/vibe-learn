#!/bin/bash
# pause-summary.sh — Stop hook
# Writes .vibe-learn/pause-summary.txt: the session so far (goal, commands
# still failing, the last turn, files touched), capped at
# pause_summary_max_lines. bootstrap.sh injects it into the next session.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=identity.sh
if ! . "$SCRIPT_DIR/identity.sh" 2>/dev/null; then
  # Installs that copy hook scripts one by one may lack the helper.
  VL_SEP=$'\x1f'
  vl_resolve_harness() { printf '%s' "${VIBE_LEARN_HARNESS:-${1:-unknown}}"; }
  vl_host_config() { :; }
  vl_harness_version() { :; }
fi

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // .workspaceRoot // empty')
if [ -z "$CWD" ] && [ -n "${GROK_HOOK_EVENT:-}" ]; then
  CWD="${GROK_WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-}}"
fi
HOOK_EVENT_NAME=$(echo "$INPUT" | jq -r '.hook_event_name // .hookEventName // empty')
REASON=$(echo "$INPUT" | jq -r '.reason // empty')

if [ -z "$CWD" ]; then
  exit 0
fi

# Grok fires an extra observe-only Stop at session end. Only summarise genuine turn ends.
if [ -n "$REASON" ] && [ "$REASON" != "end_turn" ]; then
  exit 0
fi

LOG_DIR="$CWD/.vibe-learn"
SESSION_LOG="$LOG_DIR/session-log.jsonl"
SUMMARY_FILE="$LOG_DIR/pause-summary.txt"

if [ ! -f "$SESSION_LOG" ] || [ ! -s "$SESSION_LOG" ]; then
  exit 0
fi

# --- Record the model and effort that answered this turn ---
# health.sh splits a session wherever these change mid-session.
META_FILE="$LOG_DIR/session-meta.json"
META=""
[ -f "$META_FILE" ] && META=$(jq -c 'objects' "$META_FILE" 2>/dev/null)
[ -n "$META" ] || META='{}'
VL_READ_1=$(printf '%s' "$INPUT" | jq -r --arg sep "$VL_SEP" --argjson meta "$META" '
  def str: if type == "string" then . else "" end;
  [ ($meta.current_turn // 0 | tostring),
    ((.harness // $meta.harness) | str),
    ((.model_id // .model) | str),
    ((.effort | if type == "object" then .level else . end) | str),
    ((.transcript_path // .transcriptPath // $meta.transcript_path) | str),
    ((.workspaceRoot // .cwd) | str),
    ((.session_id // .sessionId // $meta.session_id) | str)
  ] | join($sep)' 2>/dev/null)
IFS="$VL_SEP" read -r TURN P_HARNESS P_MODEL P_EFFORT P_TRANSCRIPT P_ROOT P_SESSION <<EOF
$VL_READ_1
EOF
TURN_HARNESS=$(vl_resolve_harness "${P_HARNESS:-}" "${P_TRANSCRIPT:-}")
VL_READ_2=$(vl_host_config "$TURN_HARNESS" "${P_TRANSCRIPT:-}" "${P_ROOT:-$CWD}" "${P_SESSION:-}")
IFS="$VL_SEP" read -r H_MODEL H_EFFORT <<EOF
$VL_READ_2
EOF
jq -cn \
  --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg turn "${TURN:-0}" \
  --arg model "${H_MODEL:-${P_MODEL:-}}" \
  --arg effort "${H_EFFORT:-${P_EFFORT:-}}" '
  def nonempty: if . == "" then null else . end;
  {timestamp: $ts, event: "turn_end", turn: ($turn | tonumber? // 0),
   model: ($model | nonempty), effort: ($effort | nonempty)}' >> "$SESSION_LOG" 2>/dev/null || true

# --- Summarise the whole session from the session facts (lib/session.jq) ---
# Learning turns are left out, and a learning turn leaves the previous summary
# in place, so a trailing /digest never replaces the last real-work summary.

# pause_summary_max_lines from ~/.vibe-learn/config.json, overridden by the
# project's .vibe-learn/config.json. Default 20; anything under 4 counts as 4.
MAX_LINES=20
for f in "$HOME/.vibe-learn/config.json" "$LOG_DIR/config.json"; do
  [ -f "$f" ] || continue
  v=$(jq -r '.pause_summary_max_lines | numbers | floor' "$f" 2>/dev/null || true)
  [ -n "$v" ] && MAX_LINES="$v"
done
[ "$MAX_LINES" -lt 4 ] 2>/dev/null && MAX_LINES=4

# Claude Code plugin installs namespace the commands under the plugin name.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  FOOTER=" /vibe-learn:learn [question]  ·  /vibe-learn:digest  ·  /vibe-learn:quiz  ·  vibe-learn briefing"
else
  FOOTER=" /learn [question]  ·  /digest  ·  /quiz  ·  vibe-learn briefing  ·  vibe-learn audio-prep"
fi

# A Stop hook has 10 s. A very long log is read as its last TAIL_LINES events,
# preceded by the prompt that owns the first of them, so they stay in their
# own turn (a /digest stays a learning turn). The goal comes from the
# session's first prompts, read separately.
TAIL_LINES=5000
LOG_LINES=$(wc -l < "$SESSION_LOG")
GOAL=""
read_log() {
  if [ "$LOG_LINES" -le "$TAIL_LINES" ]; then
    cat "$SESSION_LOG"
  else
    local cut=$((LOG_LINES - TAIL_LINES + 1)) owner
    owner=$(awk -v cut="$cut" 'NR >= cut { exit } /"event": ?"user_prompt"/ { l = NR } END { print l }' "$SESSION_LOG")
    [ -n "$owner" ] && sed -n "${owner}p" "$SESSION_LOG"
    tail -n "+$cut" "$SESSION_LOG"
  fi
}
if [ "$LOG_LINES" -gt "$TAIL_LINES" ]; then
  GOAL=$(grep -m 20 -E '"event": ?"user_prompt"' "$SESSION_LOG" | jq -Rnr -L "$SCRIPT_DIR/lib" -L "$SCRIPT_DIR" \
    'include "session"; [inputs | fromjson? | objects] | session_facts({}; "") | .goal // empty' 2>/dev/null)
fi

SUMMARY=$(read_log | jq -Rnr -L "$SCRIPT_DIR/lib" -L "$SCRIPT_DIR" \
  --argjson meta "$META" --arg root "$CWD" --arg footer "$FOOTER" --argjson max "$MAX_LINES" --arg goal "$GOAL" '
  include "session";
  def times($n): if $n > 1 then " ×\($n)" else "" end;
  def clip($n): if length > $n then .[:$n - 1] + "…" else . end;

  [inputs | fromjson? | objects] | session_facts($meta; $root)
  | if $goal != "" then .goal = $goal else . end
  | select((.turns.last_is_learning | not) and ((.files | length) + (.commands | length)) > 0)
  # Open failures, one line per command (latest exit code, how many times).
  | ([.failures | to_entries[] | .value + {i: .key} | select(.fixed_by == null)]
     | group_by(.command) | map(last + {times: length}) | sort_by(.i)) as $open
  | [ "⏸ vibe-learn — this session so far:",
      (if .goal then "Goal: \(.goal | gsub("\\s+"; " ") | clip(200))" else empty end),
      (if ($open | length) > 0 then
         "", "⚠ \($open | length) command(s) still failing — worth checking before continuing:",
         ($open[:5][] | "  ✗ \(.command | clip(120)) (exit \(.exit_code))\(times(.times))"),
         (if ($open | length) > 5 then "  … and \(($open | length) - 5) more" else empty end)
       else empty end),
      (.last_turn as $t
       | if (($t.files | length) + ($t.commands | length)) > 0 then
           "", "Last turn\(if ($t.prompt // "") != "" then ": \($t.prompt | gsub("\\s+"; " ") | clip(120))" else "" end)",
           ($t.files[] | "  ✦ \({created: "Created", edited: "Edited", deleted: "Deleted"}[.action]) \(.path)"),
           ($t.commands[] | "  ✦ Ran: \(.first_line | clip(120))\(if .exit_code != 0 then " [failed ✗]" else "" end)")
         else empty end),
      (if (.files | length) > 0 then
         "", "Files this session (\(.files | length)):",
         (.files[:10][] | "  \(.path) — \([(if .created > 0 then "created" + times(.created) else empty end),
                                         (if .edited > 0 then "edited" + times(.edited) else empty end),
                                         (if .deleted > 0 then "deleted" + times(.deleted) else empty end)] | join(", "))"),
         (if (.files | length) > 10 then "  … and \((.files | length) - 10) more" else empty end)
       else empty end)
    ] as $body
  # The footer always fits; the body is cut to the cap with a pointer to /learn.
  | (if ($body | length) + 2 <= $max then $body
     else $body[:$max - 3] + ["  … more in /learn and vibe-learn briefing"] end)
    + ["", $footer]
  | join("\n")' 2>/dev/null)

# Nothing to report: no work yet, or the turn that just ended was a learning turn.
if [ -z "$SUMMARY" ]; then
  exit 0
fi

# Write to file — bootstrap.sh injects this into the next session via SessionStart
echo "$SUMMARY" > "$SUMMARY_FILE"
# Names the session that wrote the summary: bootstrap.sh drops a summary left
# by an older session, and briefing.sh shows it only on this session's page.
printf '%s' "$META" | jq -r '.session_id // empty' > "$LOG_DIR/pause-summary.session" 2>/dev/null || true

# The summary reaches the assistant only through the file. A Stop hook's
# additionalContext is not passive on Claude Code (it keeps the turn going,
# like decision: block) and Grok treats it as a keep-working gate, so Stop
# never emits it. Claude Code and Codex send "Stop" and get {"continue":true};
# Grok, Cursor and Copilot ("stop") and a payload without an event get nothing.
if [ -z "${GROK_HOOK_EVENT:-}" ] && [ "$HOOK_EVENT_NAME" = "Stop" ]; then
  printf '{"continue":true}\n'
fi
