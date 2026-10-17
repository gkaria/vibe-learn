#!/usr/bin/env bats
# scripts/lib/session.jq — the session facts every reader shares.

load test_helper

ROOT=/work/proj

# facts [META] < log  → the session_facts object for the log on stdin.
facts() {
  jq -nc -L "$SCRIPTS_DIR/lib" --argjson meta "${1:-{\}}" --arg root "$ROOT" \
    'include "session"; [inputs] | session_facts($meta; $root)'
}

fixture() { sed "s#__ROOT__#$ROOT#g" "$VIBE_LEARN_DIR/tests/fixtures/session-learning.jsonl"; }

@test "session facts take the goal from the first substantial work prompt" {
  run facts '{"session_id":"s1","harness":"claude-code"}' < <(fixture)
  [ "$status" -eq 0 ]
  [ "$(jq -r '.goal' <<<"$output")" = "Build an Express API with two routes and a test for each" ]
  [ "$(jq -c '[.goal_turn, .session_id, .harness]' <<<"$output")" = '[2,"s1","claude-code"]' ]
}

@test "session facts count work and learning turns and flag a trailing learning turn" {
  run facts < <(fixture)
  [ "$(jq -c '.turns' <<<"$output")" = '{"work":4,"learning":2,"last":6,"last_is_learning":true}' ]
}

@test "session facts list each work file once, relative to the root, with per-action counts" {
  run facts < <(fixture)
  [ "$(jq -c '.files' <<<"$output")" = '[{"path":"src/app.js","created":1,"edited":2,"deleted":0,"turns":[2,3,5]},{"path":"test/app.test.js","created":1,"edited":0,"deleted":0,"turns":[2]}]' ]
}

@test "session facts pair failures with the next success and keep learning-turn failures out" {
  run facts < <(fixture)
  [ "$(jq -c '.failures' <<<"$output")" = '[{"turn":2,"command":"npm test","exit_code":1,"fixed_by":{"turn":3,"command":"npm test"}},{"turn":5,"command":"npm run lint","exit_code":1,"fixed_by":null}]' ]
  [ "$(jq -c '.last_turn' <<<"$output")" = '{"turn":5,"files":[{"path":"src/app.js","action":"edited"}],"commands":[{"first_line":"npm run lint","exit_code":1}]}' ]
}

@test "a failure pairs with the same command first, then the same program, never an unrelated success" {
  run facts < <(printf '%s\n' \
    '{"event":"user_prompt","prompt":"go"}' \
    '{"event":"tool_use","tool":"Bash","command":"npm test","context":{"exit_code":1}}' \
    '{"event":"tool_use","tool":"Bash","command":"CI=1 pytest tests/a.py","context":{"exit_code":1}}' \
    '{"event":"tool_use","tool":"Bash","command":"cargo build","context":{"exit_code":101}}' \
    '{"event":"user_prompt","prompt":"again"}' \
    '{"event":"tool_use","tool":"Bash","command":"npm run build","context":{"exit_code":0}}' \
    '{"event":"tool_use","tool":"Bash","command":"pytest","context":{"exit_code":0}}' \
    '{"event":"tool_use","tool":"Bash","command":"npm test","context":{"exit_code":0}}' \
    '{"event":"tool_use","tool":"Bash","command":"ls","context":{"exit_code":0}}')
  [ "$(jq -c '.failures | map([.command, .fixed_by])' <<<"$output")" = '[["npm test",{"turn":2,"command":"npm test"}],["CI=1 pytest tests/a.py",{"turn":2,"command":"pytest"}],["cargo build",null]]' ]
}

@test "the goal skips typed commands and short replies, falling back to the longest early prompt" {
  run facts < <(printf '%s\n' \
    '{"event":"user_prompt","prompt":"/compact keep the plan and the open todo list please"}' \
    '{"event":"user_prompt","prompt":"yes"}' \
    '{"event":"user_prompt","prompt":"add a login page"}' \
    '{"event":"user_prompt","prompt":"ok go"}' \
    '{"event":"user_prompt","prompt":"now refactor the whole auth module into smaller files"}')
  # The typed /compact is skipped even though it is long; turn 5 is the first
  # work prompt with 6+ words, so it wins over the longest-early fallback.
  [ "$(jq -r '.goal' <<<"$output")" = "now refactor the whole auth module into smaller files" ]

  run facts < <(printf '%s\n' '{"event":"user_prompt","prompt":"/digest"}' \
    '{"event":"user_prompt","prompt":"fix it"}' '{"event":"user_prompt","prompt":"add a login page"}')
  [ "$(jq -c '[.goal, .goal_turn]' <<<"$output")" = '["add a login page",3]' ]

  run facts < <(printf '%s\n' '{"event":"user_prompt","prompt":"/quiz"}')
  [ "$(jq -c '.goal' <<<"$output")" = "null" ]
}

@test "commands keep their first line and line count; paths outside the root stay absolute" {
  run facts < <(jq -nc '
    {event: "user_prompt", prompt: "write the release notes for this version"},
    {event: "tool_use", tool: "Bash", command: "cat > notes.md <<EOF\nline one\nline two\nEOF", context: {exit_code: 0}},
    {event: "tool_use", tool: "Write", file: "./docs/notes.md", action: "created"},
    {event: "tool_use", tool: "Write", file: "/tmp/scratch.txt", action: "created"},
    {event: "tool_use", tool: "Write", file: "/work/proj-other/x.js", action: "created"},
    {event: "tool_use", tool: "Edit", file: "/work/proj/src/a.js", action: "failed"}')
  [ "$(jq -c '.commands' <<<"$output")" = '[{"turn":1,"first_line":"cat > notes.md <<EOF","lines":4,"exit_code":0}]' ]
  [ "$(jq -c '.files | map(.path)' <<<"$output")" = '["docs/notes.md","/tmp/scratch.txt","/work/proj-other/x.js"]' ]
}

@test "a Bash event without a command still yields facts" {
  run facts < <(printf '%s\n' '{"event":"user_prompt","prompt":"go"}' \
    '{"event":"tool_use","tool":"Bash","context":{"exit_code":1}}' \
    '{"event":"tool_use","tool":"Bash","command":"   ","context":{"exit_code":0}}')
  [ "$status" -eq 0 ]
  [ "$(jq -c '.failures | map([.command, .exit_code])' <<<"$output")" = '[["",1]]' ]
}

@test "session facts of an empty log are empty, not an error" {
  run facts < /dev/null
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.goal, .turns.work, (.files | length), (.failures | length), .last_turn.turn]' <<<"$output")" = '[null,0,0,0,null]' ]
}
