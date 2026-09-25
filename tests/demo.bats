#!/usr/bin/env bats

load test_helper

DEMO_DIR="$VIBE_LEARN_DIR/docs/demo"

@test "demo scripts are executable and run without delays under DEMO_FAST=1" {
  [ -x "$DEMO_DIR/quiz-demo.sh" ]
  [ -x "$DEMO_DIR/learn-demo.sh" ]

  DEMO_FAST=1 run bash "$DEMO_DIR/quiz-demo.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Question 1 of 2"
  echo "$output" | grep -q "knowledge.json"

  DEMO_FAST=1 run bash "$DEMO_DIR/learn-demo.sh"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "What just happened"
}

@test "quiz demo transcript stays aligned with the README example" {
  DEMO_FAST=1 run bash "$DEMO_DIR/quiz-demo.sh"
  echo "$output" | grep -q "express-middleware-ordering"
  grep -q "express-middleware-ordering" "$VIBE_LEARN_DIR/README.md"
}

@test "each tape writes into docs/demo and the rendered assets exist" {
  for tape in quiz learn; do
    grep -q "^Output docs/demo/$tape.gif" "$DEMO_DIR/$tape.tape"
    [ -s "$DEMO_DIR/$tape.gif" ]
  done
  grep -q "Screenshot docs/demo/social-preview.png" "$DEMO_DIR/social-preview.tape"
  [ -s "$DEMO_DIR/social-preview.png" ]
}

@test "README embeds the quiz demo" {
  grep -q "docs/demo/quiz.gif" "$VIBE_LEARN_DIR/README.md"
}

@test "briefing demo renders the index, session, and health pages without touching HOME" {
  [ -x "$DEMO_DIR/briefing-demo.sh" ]
  local real_home="$HOME"
  run bash "$DEMO_DIR/briefing-demo.sh" "$TEST_PROJECT_DIR/demo/my-api"
  [ "$status" -eq 0 ]
  local b="$TEST_PROJECT_DIR/demo/my-api/.vibe-learn/briefing"
  [ "$output" = "$b" ]
  [ -s "$b/index.html" ] && [ -s "$b/health.html" ]
  grep -q 'Tools: read 9' "$b"/sessions/*.html
  [ ! -e "$real_home/.vibe-learn/health.jsonl" ]

  run bash "$DEMO_DIR/briefing-demo.sh" "$TEST_PROJECT_DIR/demo/my-api"
  [ "$status" -eq 0 ]

  local screenshot_before screenshot_after
  screenshot_before="$(shasum "$VIBE_LEARN_DIR/docs/briefing-index.png")"
  run env CHROME=/usr/bin/false bash "$DEMO_DIR/briefing-demo.sh" --screenshots "$TEST_PROJECT_DIR/demo/my-api"
  [ "$status" -ne 0 ]
  screenshot_after="$(shasum "$VIBE_LEARN_DIR/docs/briefing-index.png")"
  [ "$screenshot_before" = "$screenshot_after" ]

  local other="$TEST_PROJECT_DIR/other/my-api"
  mkdir -p "$other"
  echo 'keep me' > "$other/sentinel.txt"
  run bash "$DEMO_DIR/briefing-demo.sh" "$other"
  [ "$status" -ne 0 ]
  [ "$(cat "$other/sentinel.txt")" = 'keep me' ]

  run bash "$DEMO_DIR/briefing-demo.sh" "$TEST_PROJECT_DIR/demo/not-my-api"
  [ "$status" -ne 0 ]
}

@test "README embeds the briefing and health screenshots" {
  for f in briefing-index briefing-session briefing-health; do
    grep -q "docs/$f.png" "$VIBE_LEARN_DIR/README.md"
    [ -s "$VIBE_LEARN_DIR/docs/$f.png" ]
  done
}
