#!/usr/bin/env bats

load test_helper

@test "cli help prints usage" {
  run bash "$SCRIPTS_DIR/cli.sh" help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "vibe-learn install"
  echo "$output" | grep -q "vibe-learn briefing"
}

@test "cli install dispatches to installer" {
  run bash "$SCRIPTS_DIR/cli.sh" install "$TEST_PROJECT_DIR" --assistant=opencode
  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT_DIR/.opencode/commands/learn.md" ]
  [ -f "$TEST_PROJECT_DIR/.opencode/plugins/vibe-learn.js" ]
}

@test "cli preserves directory-first install compatibility" {
  run bash "$SCRIPTS_DIR/cli.sh" "$TEST_PROJECT_DIR" --assistant=opencode
  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT_DIR/.opencode/commands/digest.md" ]
}

@test "cli briefing dispatches to dashboard renderer" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"timestamp":"2026-06-05T10:00:00Z","event":"user_prompt","prompt":"explain cli dispatch"}' \
    > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"

  run bash "$SCRIPTS_DIR/cli.sh" briefing "$TEST_PROJECT_DIR"

  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html" ]
}

@test "cli unknown command fails clearly" {
  run bash "$SCRIPTS_DIR/cli.sh" not-a-command
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Unknown command 'not-a-command'"
}

@test "cli audio-prep fails with helpful message when no briefing exists" {
  run bash "$SCRIPTS_DIR/cli.sh" audio-prep "$TEST_PROJECT_DIR"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "briefing"
}

@test "cli audio-prep builds the briefing when a session log exists but no pack does" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"session_id":"ap-1","started_at":"2026-10-16T09:00:00Z"}' > "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json"
  echo '{"event":"user_prompt","prompt":"Build an Express API with two routes and tests"}' \
    > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
  local fake_bin="$BATS_TEST_TMPDIR/bin" tool
  mkdir -p "$fake_bin"
  for tool in pbcopy xclip open xdg-open; do printf '#!/bin/sh\nexit 1\n' > "$fake_bin/$tool"; chmod +x "$fake_bin/$tool"; done

  run env PATH="$fake_bin:$PATH" bash "$SCRIPTS_DIR/cli.sh" audio-prep "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "NotebookLM pack: .*-ap-1-notebooklm-pack.md"
  # The prompt to paste is the pack's own opening paragraph.
  echo "$output" | grep -qx "  Create a maintainer-focused audio overview of this session. Explain what "
  [ -n "$(ls "$TEST_PROJECT_DIR"/.vibe-learn/briefing/exports/*-ap-1-notebooklm-pack.md)" ]
}

@test "cli audio-prep reports a failed briefing as a failure, and checks its arguments" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"event":"user_prompt","prompt":"build it"}' > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
  local copy="$BATS_TEST_TMPDIR/vl"
  cp -R "$SCRIPTS_DIR" "$copy"
  printf '#!/bin/bash\necho "ERROR: briefing failed" >&2\nexit 1\n' > "$copy/briefing.sh"
  run bash "$copy/audio-prep.sh" "$TEST_PROJECT_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"The briefing failed"* ]]
  [[ "$output" != *"No session log found"* ]]

  run bash "$SCRIPTS_DIR/audio-prep.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == "Usage: vibe-learn audio-prep [target-dir]"* ]]
  run bash "$SCRIPTS_DIR/audio-prep.sh" "$TEST_PROJECT_DIR" extra
  [ "$status" -eq 1 ]
}

@test "cli audio-prep finds and reports the latest NotebookLM pack" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn/briefing/exports"
  echo "# pack" > "$TEST_PROJECT_DIR/.vibe-learn/briefing/exports/2026-06-05-proj-abc-notebooklm-pack.md"

  local fake_bin
  fake_bin="$(mktemp -d)"
  printf '#!/bin/sh\nexit 1\n' > "$fake_bin/pbcopy"
  printf '#!/bin/sh\nexit 1\n' > "$fake_bin/xclip"
  printf '#!/bin/sh\nexit 1\n' > "$fake_bin/open"
  chmod +x "$fake_bin/pbcopy" "$fake_bin/xclip" "$fake_bin/open"

  run env PATH="$fake_bin:$PATH" bash "$SCRIPTS_DIR/cli.sh" audio-prep "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "notebooklm-pack.md"
  echo "$output" | grep -qi "notebooklm"
  echo "$output" | grep -q "Path:"
  ! echo "$output" | grep -q "copied to clipboard" || false

  rm -rf "$fake_bin"
}

@test "cli audio-prep picks the most recently written pack, not the last filename" {
  local exports="$TEST_PROJECT_DIR/.vibe-learn/briefing/exports"
  mkdir -p "$exports"
  # Same day: the newer session's id sorts first alphabetically.
  echo "# older" > "$exports/2026-06-05-proj-ffff-notebooklm-pack.md"
  touch -t 202606051000 "$exports/2026-06-05-proj-ffff-notebooklm-pack.md"
  echo "# newer" > "$exports/2026-06-05-proj-0000-notebooklm-pack.md"

  local fake_bin
  fake_bin="$(mktemp -d)"
  for tool in pbcopy xclip open; do
    printf '#!/bin/sh\nexit 1\n' > "$fake_bin/$tool"
    chmod +x "$fake_bin/$tool"
  done

  run env PATH="$fake_bin:$PATH" bash "$SCRIPTS_DIR/cli.sh" audio-prep "$TEST_PROJECT_DIR"
  rm -rf "$fake_bin"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "2026-06-05-proj-0000-notebooklm-pack.md"
  ! echo "$output" | grep -q "ffff"
}

@test "cli knowledge dispatches to the ledger helper in the current project" {
  cd "$TEST_PROJECT_DIR"
  bash "$SCRIPTS_DIR/knowledge.sh" record jwt-auth --label="JWT" --status=solid
  run bash "$SCRIPTS_DIR/cli.sh" knowledge forget jwt-auth
  [ "$status" -eq 0 ]
  [ "$output" = "Forgot 'jwt-auth'." ]
  [ "$(jq '.concepts | length' .vibe-learn/knowledge.json)" = 0 ]
}
