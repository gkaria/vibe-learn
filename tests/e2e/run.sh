#!/bin/bash
# run.sh — drive two real Claude Code sessions against a vibe-learn checkout
# and compare what vibe-learn recorded with tests/e2e/golden/express-api.json.
#
# Usage: tests/e2e/run.sh [checkout]     (default: the checkout holding this script)
#
# Session 1 builds the Express API in express-api/TASK.md (one deliberately
# failing test, then the fix) and runs /digest. Session 2 is one chat turn, so
# SessionStart rotates session 1 and writes its health row. The golden holds
# counts and shapes only, never model text: a number is an exact value, a
# two-number array an inclusive range.
#
# Needs claude, node, npm, jq, and CLAUDE_CODE_OAUTH_TOKEN (from
# `claude setup-token`) or ANTHROPIC_API_KEY, because the sessions run under a
# temporary HOME. Uses the network and about a minute of model time. Exits 0
# when every expectation holds; otherwise prints the mismatches, keeps the
# work directory, and exits 1.

set -euo pipefail

E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKOUT="$(cd "${1:-$E2E_DIR/../..}" && pwd)"
GOLDEN="$E2E_DIR/golden/express-api.json"
BUILD_PROMPT="Build the Express API described in TASK.md, following its steps in order."

for tool in claude node npm jq; do
  command -v "$tool" >/dev/null || { echo "run.sh: $tool is required" >&2; exit 2; }
done
if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}${ANTHROPIC_API_KEY:-}" ]; then
  echo "run.sh: set CLAUDE_CODE_OAUTH_TOKEN (claude setup-token) or ANTHROPIC_API_KEY" >&2
  exit 2
fi
[ -f "$CHECKOUT/scripts/setup.sh" ] || { echo "run.sh: not a vibe-learn checkout: $CHECKOUT" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/vibe-learn-e2e.XXXXXX")"
export HOME="$WORK/home"
export PATH="$HOME/.local/bin:$PATH"
# CLAUDE_CONFIG_DIR overrides ~/.claude; unset, claude uses the hooks setup.sh
# installs under the temporary HOME, not the maintainer's configuration.
unset CLAUDE_CONFIG_DIR
PROJECT="$WORK/e2e project"
VL="$PROJECT/.vibe-learn"
mkdir -p "$HOME" "$PROJECT"
cp "$E2E_DIR/express-api/TASK.md" "$PROJECT/"
echo "checkout: $CHECKOUT"
echo "work dir: $WORK"

bash "$CHECKOUT/scripts/setup.sh" --local --assistant=claude-code > "$WORK/setup.log" 2>&1

# Each claude run answers one prompt and ends; its output is kept for debugging.
ask() {
  (cd "$PROJECT" && claude -p --dangerously-skip-permissions "$@") >> "$WORK/claude.log" 2>&1 \
    || { echo "run.sh: claude failed; see $WORK/claude.log" >&2; exit 1; }
}

echo "session 1: build"
ask "$BUILD_PROMPT"
SESSION1=$(jq -r '.session_id' "$VL/session-meta.json")
echo "session 1: /digest"
ask --resume "$SESSION1" "/digest"

SUMMARY_GOAL=$(sed -n 's/^Goal: //p' "$VL/pause-summary.txt" 2>/dev/null | head -n 1)
(cd "$PROJECT" && vibe-learn briefing --json) > "$WORK/facts.json" 2>> "$WORK/briefing.log" || true
jq -e 'type == "object"' "$WORK/facts.json" >/dev/null 2>&1 || : > "$WORK/facts.json"

echo "session 2: chat turn (rotates session 1)"
ask "Reply with the single word: done"
(cd "$PROJECT" && vibe-learn briefing) >> "$WORK/briefing.log" 2>&1 || true
CARD=false
grep -qF -- "-$SESSION1.html" "$VL/briefing/index.html" 2>/dev/null && CARD=true
# Tool events of the build turn, from the rotated log; health counts every
# other event only if it counts learning turns as work.
BUILD_EVENTS=$(jq -s 'map(select(.event == "tool_use" and .turn == 1)) | length' "$VL/session-log.prev.jsonl" 2>/dev/null || echo null)

# One flat object of observed counts and shapes; a source that is missing
# leaves its keys out, so every expectation on it reports null.
jq -n \
  --arg summary_goal "$SUMMARY_GOAL" \
  --argjson card "$CARD" \
  --arg session1 "$SESSION1" \
  --argjson build_events "$BUILD_EVENTS" \
  --slurpfile facts "$WORK/facts.json" \
  --slurpfile health <(cat "$VL/health.jsonl" 2>/dev/null || true) '
  ($facts[0] // null) as $f
  | [$health[] | select(.session_id == $session1) | .metrics] as $rows
  | {"summary.goal": (if $summary_goal == "" then null else $summary_goal end),
     "card.previous_session": $card}
  + (if $f == null then {} else {
      "facts.goal": $f.goal,
      "facts.goal_turn": $f.goal_turn,
      "facts.turns.work": $f.turns.work,
      "facts.turns.learning": $f.turns.learning,
      "facts.files": ($f.files | length),
      "facts.commands": ($f.commands | length),
      "facts.failures": ($f.failures | length),
      "facts.failures_unfixed": ($f.failures | map(select(.fixed_by == null)) | length)
    } end)
  + (if ($rows | length) == 0 then {} else
      ["prompts", "tool_events", "bash_failures", "failed_file_ops", "check_unrecovered"]
      | map({key: "health.\(.)", value: (. as $m | $rows | map(.[$m]) | add)})
      | from_entries
      | . + {"health.learning_tool_events": (if $build_events == null then null else .["health.tool_events"] - $build_events end)}
    end)' > "$WORK/observed.json"

jq -r --slurpfile observed "$WORK/observed.json" '
  .expect | to_entries[]
  | .key as $k | .value as $want | $observed[0][$k] as $got
  | (if ($want | type) == "array"
     then ($got | type) == "number" and $got >= $want[0] and $got <= $want[1]
     else $got == $want end) as $ok
  | "\(if $ok then "ok  " else "FAIL" end) \($k): \($got | tojson)\(if $ok then "" else "  (want \($want | tojson))" end)"
  ' "$GOLDEN" | tee "$WORK/result.txt"

if grep -q '^FAIL' "$WORK/result.txt"; then
  echo "e2e: FAIL (kept $WORK)"
  exit 1
fi
echo "e2e: PASS"
rm -rf "$WORK"
