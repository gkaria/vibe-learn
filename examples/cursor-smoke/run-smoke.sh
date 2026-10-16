#!/usr/bin/env bash
# End-to-end Cursor adapter smoke: install hooks into a temp copy of this
# sample app, replay Cursor-shaped payloads through the shim, assert success.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SAMPLE="$ROOT/examples/cursor-smoke"
FIXTURES="$ROOT/tests/fixtures/cursor"
SHIM_REL=".cursor/hooks/vibe-learn.sh"

die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok — %s\n' "$*"; }
run() {
  printf '+ %s\n' "$*"
  "$@"
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

need bash
need jq
need node

PROJECT="$(mktemp -d "${TMPDIR:-/tmp}/vibe-learn-cursor-smoke.XXXXXX")"
cleanup() { rm -rf "$PROJECT"; }
trap cleanup EXIT

printf 'Cursor smoke project: %s\n' "$PROJECT"

# --- 1. Seed the sample app -------------------------------------------------
run mkdir -p "$PROJECT/src/routes"
run cp "$SAMPLE/package.json" "$PROJECT/package.json"
run cp "$SAMPLE/src/index.js" "$PROJECT/src/index.js"
run cp "$SAMPLE/src/routes/health.js" "$PROJECT/src/routes/health.js"
run cp "$SAMPLE/src/routes/health.test.js" "$PROJECT/src/routes/health.test.js"

# Prove the sample itself runs (the "app" Cursor would have built).
run bash -c "cd \"$PROJECT\" && node --test src/routes/health.test.js"
pass "sample app unit test"

# --- 2. Install vibe-learn Cursor adapter into the project ------------------
run bash "$ROOT/adapters/cursor/install.sh" "$ROOT" "$PROJECT"

[ -x "$PROJECT/$SHIM_REL" ] || die "shim missing or not executable"
[ -f "$PROJECT/.cursor/hooks.json" ] || die "hooks.json missing"
for skill in learn digest quiz explain vibe-learn; do
  [ -f "$PROJECT/.cursor/skills/$skill/SKILL.md" ] || die "skill missing: $skill"
done
pass "Cursor install (hooks + skills)"

# --- 3. Replay a Cursor turn through the shim -------------------------------
feed() {
  local fixture="$1"
  local out
  out="$(sed "s|__PROJECT_ROOT__|$PROJECT|g" "$FIXTURES/$fixture" \
    | bash "$PROJECT/$SHIM_REL")"
  printf '%s' "$out"
}

printf '+ replay sessionStart\n'
SESSION_OUT="$(feed session-start.json)"
[ -z "$SESSION_OUT" ] || die "sessionStart should be silent on first session, got: $SESSION_OUT"

printf '+ replay beforeSubmitPrompt\n'
PROMPT_OUT="$(feed before-submit-prompt.json)"
[ "$PROMPT_OUT" = '{"continue":true}' ] || die "beforeSubmitPrompt expected continue, got: $PROMPT_OUT"

printf '+ replay afterFileEdit (create)\n'
WRITE_OUT="$(feed after-file-edit-write.json)"
[ -z "$WRITE_OUT" ] || die "afterFileEdit should be silent, got: $WRITE_OUT"

printf '+ replay afterFileEdit (edit)\n'
EDIT_OUT="$(feed after-file-edit-edit.json)"
[ -z "$EDIT_OUT" ] || die "afterFileEdit edit should be silent, got: $EDIT_OUT"

printf '+ replay postToolUse Shell\n'
SHELL_OUT="$(feed post-tool-use-shell.json)"
[ -z "$SHELL_OUT" ] || die "postToolUse should be silent, got: $SHELL_OUT"

printf '+ replay stop\n'
STOP_OUT="$(feed stop.json)"
[ -z "$STOP_OUT" ] || die "stop must not emit followup_message, got: $STOP_OUT"
pass "Cursor hook replay"

# --- 4. Assert vibe-learn artifacts ----------------------------------------
LOG="$PROJECT/.vibe-learn/session-log.jsonl"
META="$PROJECT/.vibe-learn/session-meta.json"
SUMMARY="$PROJECT/.vibe-learn/pause-summary.txt"

[ -f "$LOG" ] || die "session-log.jsonl missing"
[ -f "$META" ] || die "session-meta.json missing"
[ -f "$SUMMARY" ] || die "pause-summary.txt missing"

[ "$(jq -r '.harness' "$META")" = "cursor" ] || die "expected harness=cursor"
[ "$(jq -r '.session_id' "$META")" = "cursor-smoke-sess" ] || die "unexpected session_id"
[ "$(jq -r '.model' "$META")" = "composer-2" ] || die "unexpected model"

grep -q '"event":"user_prompt"' "$LOG" || die "prompt event missing"
grep -q 'Build a simple /health endpoint' "$LOG" || die "prompt text missing"
[ "$(jq -r 'select(.tool=="Write") | .action' "$LOG" | head -1)" = "created" ] || die "Write/created missing"
[ "$(jq -r 'select(.tool=="Edit") | .action' "$LOG" | head -1)" = "edited" ] || die "Edit/edited missing"
[ "$(jq -r 'select(.tool=="Bash") | .command' "$LOG" | head -1)" = "node --test src/routes/health.test.js" ] \
  || die "Bash command missing"
[ "$(jq -r 'select(.tool=="Bash") | .context.exit_code' "$LOG" | head -1)" = "0" ] || die "Bash exit_code missing"

grep -q 'Build a simple /health endpoint' "$SUMMARY" || die "pause summary missing goal"
grep -q 'Created '"$PROJECT"'/src/routes/health.js' "$SUMMARY" \
  || grep -q 'Created src/routes/health.js' "$SUMMARY" \
  || grep -q 'health.js' "$SUMMARY" || die "pause summary missing created file"
grep -q 'Ran: node --test src/routes/health.test.js' "$SUMMARY" || die "pause summary missing shell"
grep -q '/learn' "$SUMMARY" || die "pause summary missing /learn menu"

# Skills path a Cursor (or Grok-plugin) agent would read for /learn.
grep -q 'session-log.jsonl' "$PROJECT/.cursor/skills/learn/SKILL.md" \
  || die "learn skill does not reference session-log.jsonl"
grep -q 'pause-summary.txt' "$PROJECT/.cursor/skills/learn/SKILL.md" \
  || die "learn skill does not reference pause-summary.txt"

# Knowledge helper reachable the same way skills document.
run bash "$ROOT/scripts/knowledge.sh" touch cursor-smoke-health \
  --label="Cursor smoke /health route" --dir="$PROJECT"
[ -f "$PROJECT/.vibe-learn/knowledge.json" ] || die "knowledge.json not written"
jq -e '.concepts[] | select(.name=="cursor-smoke-health")' \
  "$PROJECT/.vibe-learn/knowledge.json" >/dev/null \
  || die "knowledge concept missing"

pass "session artifacts + knowledge helper"

# --- 5. Plugin packaging sanity (Cursor + Grok submission surface) ----------
jq -e '.name == "vibe-learn"' "$ROOT/.cursor-plugin/plugin.json" >/dev/null \
  || die "cursor plugin.json invalid"
[ -f "$ROOT/adapters/grok/skills/vibe-learn/SKILL.md" ] \
  || die "Grok vibe-learn skill missing (needed for Grok bot plugin submit)"
[ -f "$ROOT/adapters/grok/hooks.json" ] || die "Grok hooks.json missing"
pass "Cursor plugin manifest + Grok adapter present"

printf '\nPASS: vibe-learn Cursor smoke completed successfully.\n'
printf 'Evidence:\n'
printf '  project=%s\n' "$PROJECT"
printf '  events=%s\n' "$(wc -l < "$LOG" | tr -d ' ')"
printf '  harness=%s model=%s\n' "$(jq -r '.harness' "$META")" "$(jq -r '.model' "$META")"
printf '  summary_bytes=%s\n' "$(wc -c < "$SUMMARY" | tr -d ' ')"
# Keep a copy of key evidence outside the temp dir for the caller (trap cleans PROJECT).
EVIDENCE_DIR="${VIBE_LEARN_SMOKE_EVIDENCE:-}"
if [ -n "$EVIDENCE_DIR" ]; then
  mkdir -p "$EVIDENCE_DIR"
  cp "$LOG" "$META" "$SUMMARY" "$EVIDENCE_DIR/"
  printf '  evidence_copied_to=%s\n' "$EVIDENCE_DIR"
fi
