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
