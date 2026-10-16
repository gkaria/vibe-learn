#!/usr/bin/env bats
# Thin wrapper so CI runs the Cursor end-to-end smoke sample.

load test_helper

SMOKE_SCRIPT="$VIBE_LEARN_DIR/examples/cursor-smoke/run-smoke.sh"

@test "cursor smoke sample script is executable and documents itself" {
  [ -f "$SMOKE_SCRIPT" ]
  [ -x "$SMOKE_SCRIPT" ]
  [ -f "$VIBE_LEARN_DIR/examples/cursor-smoke/README.md" ]
  [ -f "$VIBE_LEARN_DIR/examples/cursor-smoke/src/routes/health.js" ]
  for f in session-start before-submit-prompt after-file-edit-write \
           after-file-edit-edit post-tool-use-shell stop; do
    [ -f "$VIBE_LEARN_DIR/tests/fixtures/cursor/${f}.json" ]
  done
}

@test "cursor smoke end-to-end: install, replay Cursor hooks, assert session artifacts" {
  run bash "$SMOKE_SCRIPT"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: vibe-learn Cursor smoke completed successfully."* ]]
  [[ "$output" == *"ok — Cursor install (hooks + skills)"* ]]
  [[ "$output" == *"ok — Cursor hook replay"* ]]
  [[ "$output" == *"ok — session artifacts + knowledge helper"* ]]
}
