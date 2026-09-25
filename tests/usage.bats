#!/usr/bin/env bats

load test_helper

# usage.sh — tool families and skills per session, read from each host's own
# record. The fixtures pin the (undocumented) formats observed on real hosts.

usage() {
  bash -c '. "$1/usage.sh"; shift; vl_session_usage "$@"' _ "$SCRIPTS_DIR" "$@"
}

@test "claude-code: tool_use blocks become families; Skill calls and SKILL.md reads name skills" {
  local t="$TEST_PROJECT_DIR/claude.jsonl"
  cat > "$t" <<'EOF'
{"type":"user","timestamp":"2026-09-25T10:00:00.000Z","message":{"content":"hi"}}
{"type":"assistant","timestamp":"2026-09-25T10:00:01.000Z","message":{"model":"claude-opus-5.5","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/p/src/a.ts"}},{"type":"tool_use","name":"Grep","input":{"pattern":"x"}}]}}
{"type":"assistant","timestamp":"2026-09-25T10:00:02.000Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"npm test"}},{"type":"tool_use","name":"Edit","input":{"file_path":"/p/src/a.ts"}}]}}
{"type":"assistant","timestamp":"2026-09-25T10:00:03.000Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"learn","args":"what happened"}},{"type":"tool_use","name":"Read","input":{"file_path":"/Users/me/.claude/skills/pdf-toolkit/SKILL.md"}}]}}
{"type":"assistant","timestamp":"2026-09-25T10:00:04.000Z","message":{"content":[{"type":"tool_use","name":"mcp__Claude_Browser__navigate","input":{"url":"https://secret.example"}},{"type":"tool_use","name":"Agent","input":{}},{"type":"tool_use","name":"WebFetch","input":{}}]}}
not json
EOF
  run usage claude-code "$t" "" "" ""
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '.tools')" = '{"read":2,"edit":1,"mcp:claude_browser":1,"search":1,"shell":1,"skill":1,"subagent":1,"web":1}' ]
  [ "$(echo "$output" | jq -c '.skills')" = '{"learn":1,"pdf-toolkit":1}' ]
  # Arguments never leave: no URLs, commands, or file paths.
  ! echo "$output" | grep -q -e secret -e 'npm test' -e src/a.ts
}

@test "claude-code: lines from before the session started are skipped" {
  local t="$TEST_PROJECT_DIR/claude.jsonl"
  cat > "$t" <<'EOF'
{"type":"assistant","timestamp":"2026-09-24T09:00:00.000Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{}}]}}
{"type":"assistant","timestamp":"2026-09-25T10:00:01.000Z","message":{"content":[{"type":"tool_use","name":"Read","input":{}}]}}
EOF
  run usage claude-code "$t" "" "" "2026-09-25T10:00:00Z"
  [ "$(echo "$output" | jq -c '.tools')" = '{"read":1}' ]
}

@test "codex: function, custom, and web-search calls; MCP namespaces; injected and read skills" {
  local t="$TEST_PROJECT_DIR/rollout.jsonl"
  cat > "$t" <<'EOF'
{"timestamp":"2026-09-25T10:00:00.000Z","type":"session_meta","payload":{"cli_version":"0.153.0"}}
{"timestamp":"2026-09-25T10:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<skill>\n<name>hatch-pet</name>\n<path>/Users/me/.codex/skills/hatch-pet/SKILL.md</path>\n---"}]}}
{"timestamp":"2026-09-25T10:00:02.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\"cmd\":\"sed -n '1,240p' /Users/me/.codex/skills/.system/imagegen/SKILL.md\"}"}}
{"timestamp":"2026-09-25T10:00:03.000Z","type":"response_item","payload":{"type":"custom_tool_call","name":"apply_patch","input":"*** Begin Patch"}}
{"timestamp":"2026-09-25T10:00:04.000Z","type":"response_item","payload":{"type":"function_call","name":"js","namespace":"mcp__node_repl","arguments":"{}"}}
{"timestamp":"2026-09-25T10:00:05.000Z","type":"response_item","payload":{"type":"function_call","name":"_get_status","namespace":"mcp__codex_apps__sites","arguments":"{}"}}
{"timestamp":"2026-09-25T10:00:06.000Z","type":"response_item","payload":{"type":"web_search_call","status":"completed"}}
{"timestamp":"2026-09-25T10:00:07.000Z","type":"response_item","payload":{"type":"function_call","name":"spawn_agent","arguments":"{}"}}
{"timestamp":"2026-09-25T10:00:08.000Z","type":"response_item","payload":{"type":"function_call","name":"update_plan","arguments":"{}"}}
{"timestamp":"2026-09-25T10:00:09.000Z","type":"response_item","payload":{"type":"function_call_output","call_id":"x"}}
EOF
  run usage codex "$t" "" "" ""
  [ "$(echo "$output" | jq -c '.tools')" = '{"edit":1,"mcp:codex_apps":1,"mcp:node_repl":1,"plan":1,"shell":1,"subagent":1,"web":1}' ]
  [ "$(echo "$output" | jq -c '.skills')" = '{"hatch-pet":1,"imagegen":1}' ]
}

@test "cursor: model-side names, CallDynamicTool as its MCP namespace, SKILL.md reads" {
  local t="$TEST_PROJECT_DIR/cursor.jsonl"
  cat > "$t" <<'EOF'
{"role":"user","message":{"content":[{"type":"text","text":"hi"}]}}
{"role":"assistant","message":{"content":[{"type":"text","text":"ok"},{"type":"tool_use","name":"Read","input":{"path":"/Users/me/.cursor/skills-cursor/canvas/SKILL.md"}},{"type":"tool_use","name":"StrReplace","input":{"path":"a"}}]}}
{"role":"assistant","message":{"content":[{"type":"tool_use","name":"Shell","input":{"command":"ls"}},{"type":"tool_use","name":"CallDynamicTool","input":{"namespace":"cursor-ide-browser","toolName":"browser_navigate"}},{"type":"tool_use","name":"Task","input":{}},{"type":"tool_use","name":"AskQuestion","input":{}}]}}
EOF
  run usage cursor "$t" "" "" ""
  [ "$(echo "$output" | jq -c '.tools')" = '{"edit":1,"mcp:cursor-ide-browser":1,"other":1,"read":1,"shell":1,"subagent":1}' ]
  [ "$(echo "$output" | jq -c '.skills')" = '{"canvas":1}' ]
}

@test "grok: chat_history tool_calls under GROK_HOME, keyed by the @uri workspace root" {
  local root="/work/my app" sid="01abc"
  local dir="$HOME/.grok/sessions/%2Fwork%2Fmy%20app/$sid"
  mkdir -p "$dir"
  cat > "$dir/chat_history.jsonl" <<'EOF'
{"type":"system","content":"x"}
{"type":"assistant","tool_calls":[{"id":"1","name":"read_file","arguments":"{\"target_file\":\"/Users/me/.grok/skills/vibe-learn/SKILL.md\"}"},{"id":"2","name":"run_terminal_command","arguments":"{}"}]}
{"type":"assistant","tool_calls":[{"id":"3","name":"search_replace","arguments":"{}"},{"id":"4","name":"github__create_issue","arguments":"{}"}]}
EOF
  run usage grok "" "$root" "$sid" ""
  [ "$(echo "$output" | jq -c '.tools')" = '{"edit":1,"mcp:github":1,"read":1,"shell":1}' ]
  [ "$(echo "$output" | jq -c '.skills')" = '{"vibe-learn":1}' ]
}

@test "opencode: tool parts for the session from opencode.db" {
  command -v sqlite3 >/dev/null || skip "sqlite3 not installed"
  local db="$HOME/.local/share/opencode/opencode.db"
  mkdir -p "$(dirname "$db")"
  sqlite3 "$db" "CREATE TABLE part (id text PRIMARY KEY, message_id text, session_id text, time_created integer, time_updated integer, data text);
    INSERT INTO part VALUES ('1','m','ses_A',1,1,'{\"type\":\"tool\",\"tool\":\"read\",\"state\":{\"input\":{\"filePath\":\"/Users/me/.config/opencode/skills/review/SKILL.md\"}}}');
    INSERT INTO part VALUES ('2','m','ses_A',2,2,'{\"type\":\"tool\",\"tool\":\"skill\",\"state\":{\"input\":{\"name\":\"deploy\"}}}');
    INSERT INTO part VALUES ('3','m','ses_A',3,3,'{\"type\":\"tool\",\"tool\":\"bash\",\"state\":{\"input\":{\"command\":\"ls\"}}}');
    INSERT INTO part VALUES ('4','m','ses_A',4,4,'{\"type\":\"text\",\"text\":\"hi\"}');
    INSERT INTO part VALUES ('5','m','ses_B',5,5,'{\"type\":\"tool\",\"tool\":\"glob\",\"state\":{}}');"
  run usage opencode "" "" "ses_A" ""
  [ "$(echo "$output" | jq -c '.tools')" = '{"read":1,"shell":1,"skill":1}' ]
  [ "$(echo "$output" | jq -c '.skills')" = '{"deploy":1,"review":1}' ]
  # Session ids are validated before they reach SQL.
  run usage opencode "" "" "ses_A' OR '1'='1" ""
  [ "$output" = "null" ]
}

@test "unreadable or unknown sources yield null, never an error" {
  run usage claude-code "$TEST_PROJECT_DIR/missing.jsonl" "" "" ""
  [ "$status" -eq 0 ]; [ "$output" = "null" ]
  run usage unknown "" "" "" ""
  [ "$output" = "null" ]
  run usage grok "" "/nowhere" "x" ""
  [ "$output" = "null" ]
}

@test "a readable transcript with no tool calls is an empty map, not null" {
  echo '{"type":"user","message":{"content":"hi"}}' > "$TEST_PROJECT_DIR/c.jsonl"
  run usage claude-code "$TEST_PROJECT_DIR/c.jsonl" "" "" ""
  [ "$output" = '{"tools":{},"skills":{}}' ]
}

@test "health.sh puts session usage and typed commands on the first segment only" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  local t="$TEST_PROJECT_DIR/claude.jsonl"
  echo '{"type":"assistant","timestamp":"2026-09-25T10:00:01.000Z","message":{"content":[{"type":"tool_use","name":"Read","input":{}},{"type":"tool_use","name":"Skill","input":{"skill":"quiz"}}]}}' > "$t"
  jq -n --arg t "$t" '{session_id:"s1",started_at:"2026-09-25T10:00:00Z",harness:"claude-code",model:"m1",transcript_path:$t}' \
    > "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json"
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl" <<'EOF'
{"timestamp":"2026-09-25T10:00:00Z","event":"user_prompt","prompt":"/learn what happened"}
{"timestamp":"2026-09-25T10:00:01Z","event":"tool_use","tool":"Bash","command":"ls","action":"ran","context":{"exit_code":0}}
{"timestamp":"2026-09-25T10:00:02Z","event":"turn_end","turn":1,"model":"m1","effort":null}
{"timestamp":"2026-09-25T10:01:00Z","event":"user_prompt","prompt":"/Users/me/notes.txt is wrong"}
{"timestamp":"2026-09-25T10:01:01Z","event":"tool_use","tool":"Bash","command":"ls","action":"ran","context":{"exit_code":0}}
{"timestamp":"2026-09-25T10:01:02Z","event":"turn_end","turn":2,"model":"m2","effort":null}
{"timestamp":"2026-09-25T10:02:00Z","event":"user_prompt","prompt":"$pr-review please"}
EOF
  run bash "$SCRIPTS_DIR/health.sh" "$TEST_PROJECT_DIR/.vibe-learn"
  [ "$(echo "$output" | wc -l | tr -d ' ')" = "2" ]
  [ "$(echo "$output" | head -1 | jq -c '.usage')" = '{"tools":{"read":1,"skill":1},"skills":{"quiz":1},"commands":{"learn":1,"pr-review":1}}' ]
  [ "$(echo "$output" | tail -1 | jq -c '.usage')" = "null" ]
}

@test "health.sh without a readable transcript still records typed commands" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl" <<'EOF'
{"timestamp":"2026-09-25T10:00:00Z","event":"user_prompt","prompt":"/digest"}
{"timestamp":"2026-09-25T10:00:01Z","event":"tool_use","tool":"Bash","command":"ls","action":"ran","context":{"exit_code":0}}
EOF
  run bash "$SCRIPTS_DIR/health.sh" "$TEST_PROJECT_DIR/.vibe-learn"
  [ "$(echo "$output" | jq -c '.usage')" = '{"tools":null,"skills":null,"commands":{"digest":1}}' ]
}
