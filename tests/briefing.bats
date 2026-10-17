#!/usr/bin/env bats

load test_helper

write_sample_session() {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json" <<'JSON'
{"session_id":"dash-test","started_at":"2026-06-05T10:00:00Z","event_count":4}
JSON
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl" <<'JSONL'
{"timestamp":"2026-06-05T10:00:00Z","event":"user_prompt","prompt":"Add OpenCode support and dashboard"}
{"timestamp":"2026-06-05T10:00:05Z","event":"tool_use","tool":"Write","file":"adapters/opencode/install.sh","action":"created","context":{"new_file":true}}
{"timestamp":"2026-06-05T10:00:10Z","event":"tool_use","tool":"Edit","file":"scripts/setup.sh","action":"edited","context":{}}
{"timestamp":"2026-06-05T10:00:15Z","event":"tool_use","tool":"Bash","command":"bats tests/","action":"ran","context":{"exit_code":0}}
{"timestamp":"2026-06-05T10:00:20Z","event":"tool_use","tool":"Bash","command":"npm test","action":"ran","context":{"exit_code":1}}
JSONL
  cat > "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt" <<'TXT'
vibe-learn — what just happened:
Created OpenCode adapter files and ran tests.
TXT
}

session_file_for_test_project() {
  find "$TEST_PROJECT_DIR/.vibe-learn/briefing/sessions" -maxdepth 1 -type f -name '*.html' | head -1
}

pack_file_for_test_project() {
  find "$TEST_PROJECT_DIR/.vibe-learn/briefing/exports" -maxdepth 1 -type f -name '*-notebooklm-pack.md' | head -1
}

@test "briefing writes placeholder when session log is missing" {
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html" ]
  grep -q "No vibe-learn session log" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
}

@test "briefing generates index session page and NotebookLM pack" {
  write_sample_session

  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html" ]
  [ -f "$(session_file_for_test_project)" ]
  [ -f "$(pack_file_for_test_project)" ]
}

@test "briefing session page contains expected sections" {
  write_sample_session
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  local session_file
  session_file="$(session_file_for_test_project)"

  grep -q "Session brief" "$session_file"
  grep -q "Session Timeline" "$session_file"
  grep -q "File Tour" "$session_file"
  grep -q "Command Log" "$session_file"
  grep -q "Study Queue" "$session_file"
  grep -q "Audio Export" "$session_file"
}

@test "briefing marks failed commands" {
  write_sample_session
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  local session_file
  session_file="$(session_file_for_test_project)"

  grep -q "failed 1" "$session_file"
  grep -q "What could break" "$session_file"
}

@test "briefing has no external asset references" {
  write_sample_session
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  ! grep -R 'src="https\?://' "$TEST_PROJECT_DIR/.vibe-learn/briefing" || false
  ! grep -R 'href="https\?://' "$TEST_PROJECT_DIR/.vibe-learn/briefing"
}

@test "NotebookLM pack includes suggested audio framing" {
  write_sample_session
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  local pack
  pack="$(pack_file_for_test_project)"

  # The framing is the pack's first paragraph, right under the title.
  [ "$(sed -n 1p "$pack")" = "# $(basename "$TEST_PROJECT_DIR"): session briefing for 2026-06-05" ]
  [[ "$(sed -n 3p "$pack")" == "Create a maintainer-focused audio overview of this session."* ]]
}

@test "briefing index lists previously generated sessions" {
  write_sample_session
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn/briefing/sessions"
  echo '<!doctype html><title>older</title>' > "$TEST_PROJECT_DIR/.vibe-learn/briefing/sessions/2026-06-04-old-session.html"

  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  grep -q "2026-06-04-old-session" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
  grep -q "dash-test" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
  grep -q "Previously generated session briefing" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
}

@test "briefing accepts latest flag as current-session generation" {
  write_sample_session

  run bash "$SCRIPTS_DIR/briefing.sh" --latest "$TEST_PROJECT_DIR"

  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html" ]
  grep -q "dash-test" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
}

@test "briefing caps git diff excerpts" {
  write_sample_session
  git -C "$TEST_PROJECT_DIR" init >/dev/null
  printf 'before\n' > "$TEST_PROJECT_DIR/large-diff.txt"
  git -C "$TEST_PROJECT_DIR" add large-diff.txt
  printf 'after-' > "$TEST_PROJECT_DIR/large-diff.txt"
  printf 'x%.0s' {1..14000} >> "$TEST_PROJECT_DIR/large-diff.txt"
  printf 'TAIL_MARKER\n' >> "$TEST_PROJECT_DIR/large-diff.txt"

  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  local session_file pack
  session_file="$(session_file_for_test_project)"
  pack="$(pack_file_for_test_project)"

  grep -q "large-diff.txt" "$session_file"
  refute_grep "TAIL_MARKER" "$session_file"
  refute_grep "TAIL_MARKER" "$pack"
}

@test "briefing CSS wraps long generated labels" {
  write_sample_session
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  grep -q "overflow-wrap:anywhere" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
  grep -q "overflow-wrap:anywhere" "$(session_file_for_test_project)"
  grep -q "word-break:break-word" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
  grep -q "min-width:0" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
  grep -q "overflow-x:hidden" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
  grep -q "max-width:100%" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
}

@test "briefing index lists the current session before older same-day sessions" {
  write_sample_session
  local sessions="$TEST_PROJECT_DIR/.vibe-learn/briefing/sessions"
  mkdir -p "$sessions"
  # Sorts after the current session's filename, but was written earlier.
  echo '<!doctype html><title>older</title>' > "$sessions/2026-06-05-zzz-older.html"
  touch -t 202606051000 "$sessions/2026-06-05-zzz-older.html"

  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  local index="$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
  local current older
  current=$(grep -n 'class="card-title">.*dash-test' "$index" | cut -d: -f1)
  older=$(grep -n 'class="card-title">2026-06-05-zzz-older' "$index" | cut -d: -f1)
  [ -n "$current" ]
  [ -n "$older" ]
  [ "$current" -lt "$older" ]
}

@test "briefing timeline filters can hide items" {
  write_sample_session
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  # The filter buttons set li.hidden; the flex rule on timeline items must not override it.
  grep -q 'ol.timeline li\[hidden\]{display:none;}' "$(session_file_for_test_project)"
}

write_learning_session() {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"session_id":"learn-test","started_at":"2026-10-16T09:00:00Z"}' > "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json"
  sed "s#__ROOT__#$TEST_PROJECT_DIR#g" "$VIBE_LEARN_DIR/tests/fixtures/session-learning.jsonl" \
    > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
}

@test "briefing goal and counts leave out learning turns and the timeline marks them" {
  write_learning_session
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]

  local index="$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html" session
  session="$(session_file_for_test_project)"
  # app.js (created and edited) and app.test.js; npm install, npm test x2, lint.
  grep -q '<span class="tag">2 files</span>' "$index"
  grep -q '<span class="tag">4 commands</span>' "$index"
  grep -q '2 failed' "$index"
  # The goal is the build prompt, not the trailing /learn.
  grep -q '<p class="card-goal">Build an Express API with two routes and a test for each</p>' "$index"
  # Turn 4 (prompt, ls, digest write) and turn 6 (prompt, cat).
  [ "$(grep -c 'data-learning="true"' "$session")" -eq 5 ]
  refute_grep 'class="command-row[^"]*"[^>]*><code class="cmd-text">ls .vibe-learn/digests' "$session"
}

# --- --log/--meta, --if-stale, and the lock ----------------------------------

@test "briefing --if-stale skips a fresh page and rebuilds after the log or ledger changes" {
  write_learning_session
  local vl="$TEST_PROJECT_DIR/.vibe-learn" page
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  page="$(session_file_for_test_project)"
  touch -t 202601010000 "$vl/session-log.jsonl"

  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --if-stale
  [ "$status" -eq 0 ]
  [ "$output" = "Session briefing is up to date: $page" ]

  sleep 1
  # A work turn: it edits a file, so it is not a follow-up to the trailing /learn.
  printf '%s\n' '{"event":"user_prompt","prompt":"one more thing"}' \
    '{"event":"tool_use","tool":"Edit","file":"src/app.js","action":"edited","context":{}}' >> "$vl/session-log.jsonl"
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --if-stale
  [[ "$output" == *"Session briefing:"* ]]

  sleep 1
  echo '{"version":1,"concepts":[]}' > "$vl/knowledge.json"
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --if-stale
  [[ "$output" == *"Session briefing:"* ]]
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --if-stale
  [[ "$output" == *"up to date"* ]]
}

@test "briefing --if-stale with an empty log keeps the existing index" {
  write_learning_session
  local vl="$TEST_PROJECT_DIR/.vibe-learn"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  : > "$vl/session-log.jsonl"
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --if-stale
  [ "$status" -eq 0 ]
  [ "$output" = "No session activity to brief yet." ]
  refute_grep "No session data yet" "$vl/briefing/index.html"
}

@test "two briefing runs at once both finish and leave whole, uninterleaved pages" {
  write_learning_session
  local vl="$TEST_PROJECT_DIR/.vibe-learn" page
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" > "$BATS_TEST_TMPDIR/a.out" 2>&1 &
  local a=$!
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" > "$BATS_TEST_TMPDIR/b.out" 2>&1 &
  local b=$!
  wait "$a"; wait "$b"

  page="$(session_file_for_test_project)"
  [ "$(ls "$vl/briefing/sessions"/*.html | wc -l | tr -d ' ')" -eq 1 ]
  for f in "$page" "$vl/briefing/index.html"; do
    [ "$(grep -ci '<!doctype html>' "$f")" -eq 1 ]
    [ "$(grep -c '</html>' "$f")" -eq 1 ]
    [ "$(tail -n 1 "$f")" = "</html>" ]
  done
  [ "$(grep -c '<script>' "$page")" -eq "$(grep -c '</script>' "$page")" ]
}

@test "--if-stale stays up to date through a /learn turn and rebuilds after new work" {
  write_learning_session
  local vl="$TEST_PROJECT_DIR/.vibe-learn"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  # What a host appends around /learn: the prompt, its own commands, turn_end.
  jq -cn --arg cwd "$TEST_PROJECT_DIR" '{cwd: $cwd, prompt: "/learn why did the test fail?"}' | bash "$SCRIPTS_DIR/capture-prompt.sh"
  printf '%s\n' '{"event":"tool_use","tool":"Bash","command":"vibe-learn briefing --if-stale","action":"ran","context":{"exit_code":0}}' \
    '{"event":"turn_end","model":"m","effort":"high"}' >> "$vl/session-log.jsonl"
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --if-stale
  [[ "$output" == "Session briefing is up to date: "* ]]

  printf '%s\n' '{"event":"user_prompt","prompt":"add a health route"}' \
    '{"event":"tool_use","tool":"Edit","file":"src/app.js","action":"edited"}' >> "$vl/session-log.jsonl"
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --if-stale
  [[ "$output" == *"Session briefing:"* ]]
}

@test "--if-stale rebuilds a page left by a run that was killed before it finished" {
  write_learning_session
  local vl="$TEST_PROJECT_DIR/.vibe-learn" page
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  page="$(session_file_for_test_project)"
  # A killed run: the page was written, the index and stamp were not.
  rm -rf "$vl/briefing/.stamps"
  echo "half a page" > "$page"
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --if-stale
  [[ "$output" == *"Session briefing:"* ]]
  [ "$(tail -n 1 "$page")" = "</html>" ]
  [ -z "$(ls -d "$vl"/briefing/.work.* 2>/dev/null)" ]
}

@test "a rotation while the run copies the session builds one session, named from its own meta" {
  write_learning_session
  local vl="$TEST_PROJECT_DIR/.vibe-learn" bin="$BATS_TEST_TMPDIR/bin" page
  mkdir -p "$bin"
  # The first copy of the log finds the session rotated: the next session's
  # meta and log replace the pair after the meta was copied.
  cat > "$bin/cp" <<STUB
#!/bin/bash
if [ "\$1" = "$vl/session-log.jsonl" ] && [ ! -e "$bin/rotated" ]; then
  touch "$bin/rotated"
  mv "$vl/session-log.jsonl" "$vl/session-log.prev.jsonl"
  echo '{"session_id":"next-two","started_at":"2026-10-17T08:00:00Z"}' > "$vl/session-meta.json"
  echo '{"event":"user_prompt","prompt":"Add the beta delete endpoint with its tests"}' > "$vl/session-log.jsonl"
fi
exec /bin/cp "\$@"
STUB
  chmod +x "$bin/cp"
  PATH="$bin:$PATH" bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null

  [ -e "$bin/rotated" ]
  [ "$(cd "$vl/briefing/sessions" && ls *.html)" = "2026-10-17-$(basename "$TEST_PROJECT_DIR" | tr '[:upper:]' '[:lower:]')-next-two.html" ]
  page="$(session_file_for_test_project)"
  grep -q "Add the beta delete endpoint" "$page"
  refute_grep "Build an Express API" "$page"
}

@test "briefing names a page for an id with no slug-safe characters and escapes the project name" {
  local dir="$BATS_TEST_TMPDIR/x<b>y" vl
  vl="$dir/.vibe-learn"
  mkdir -p "$vl"
  echo '{"session_id":"///","started_at":"garbage"}' > "$vl/session-meta.json"
  echo '{"event":"user_prompt","prompt":"Build the thing with tests"}' > "$vl/session-log.jsonl"
  run bash "$SCRIPTS_DIR/briefing.sh" "$dir"
  [ "$status" -eq 0 ]
  [ "$(cd "$vl/briefing/sessions" && ls *.html)" = "$(date -u +%Y-%m-%d)-x-b-y-$(printf '%s' /// | cksum | cut -d ' ' -f 1).html" ]
  grep -q 'x&lt;b&gt;y' "$vl/briefing/index.html"
  refute_grep 'x<b>y' "$vl/briefing/index.html"
}

@test "the NotebookLM pack skips malformed lines and leaves learning turns out" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  printf '%s\n' '{"event":"user_prompt","prompt":"Build the alpha module with tests"}' '{broken' \
    '{"event":"tool_use","tool":"Write","file":"src/alpha.js","action":"created"}' \
    '{"event":"user_prompt","prompt":"/digest"}' > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  local pack; pack="$(pack_file_for_test_project)"
  grep -qx 'Turn 1: you asked "Build the alpha module with tests". The agent created `src/alpha.js`.' "$pack"
  grep -q '1 work turn in total, plus 1 learning turn' "$pack"
  refute_grep '/digest"' "$pack"
}

@test "a run with no session log keeps an existing briefing index" {
  write_learning_session
  local vl="$TEST_PROJECT_DIR/.vibe-learn"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  rm "$vl/session-log.jsonl"
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]
  refute_grep "No session data yet" "$vl/briefing/index.html"
}

@test "every host's learn and digest prompts refresh the briefing with --if-stale" {
  local f n=0
  for f in "$VIBE_LEARN_DIR"/adapters/claude-code/commands/{learn,digest}.md \
           "$VIBE_LEARN_DIR"/adapters/{codex/prompts,opencode/commands,grok/commands}/{learn,digest}.md \
           "$VIBE_LEARN_DIR"/adapters/{cursor,copilot-cli}/skills/{learn,digest}/SKILL.md \
           "$VIBE_LEARN_DIR"/adapters/{codex,grok,cursor,copilot-cli}/skills/vibe-learn/SKILL.md; do
    grep -q 'vibe-learn briefing --if-stale' "$f" || { echo "missing: $f"; return 1; }
    n=$((n + 1))
  done
  [ "$n" -eq 16 ]
  # /digest records concepts after its first refresh; a second one puts them on the page.
  for f in "$VIBE_LEARN_DIR"/adapters/claude-code/commands/digest.md \
           "$VIBE_LEARN_DIR"/adapters/{codex/prompts,opencode/commands,grok/commands}/digest.md \
           "$VIBE_LEARN_DIR"/adapters/{cursor,copilot-cli}/skills/digest/SKILL.md; do
    grep -q 'run the briefing refresh from the start of these instructions once more' "$f" || { echo "no second refresh: $f"; return 1; }
  done
}

@test "the page shows the pause summary only when this session wrote it" {
  write_sample_session
  local vl="$TEST_PROJECT_DIR/.vibe-learn"
  # The previous session's summary, still in place before this session's first Stop.
  echo older-session > "$vl/pause-summary.session"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  refute_grep "Created OpenCode adapter files" "$(session_file_for_test_project)"

  echo dash-test > "$vl/pause-summary.session"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  grep -q "Created OpenCode adapter files" "$(session_file_for_test_project)"
}

@test "a missing page template stops the briefing with a clear error, not a blank page" {
  write_sample_session
  local copy="$BATS_TEST_TMPDIR/scripts"
  cp -R "$SCRIPTS_DIR" "$copy"
  rm "$copy/lib/briefing-health.html"
  run bash "$copy/briefing.sh" "$TEST_PROJECT_DIR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"briefing-health.html is missing"*"reinstall vibe-learn"* ]]
  [ ! -e "$TEST_PROJECT_DIR/.vibe-learn/briefing" ]
}

@test "briefing --json prints the learning fixture's facts, matching the golden file" {
  write_learning_session
  local vl="$TEST_PROJECT_DIR/.vibe-learn" slug
  jq '. + {harness: "claude-code", model: "claude-opus-5-5"}' "$vl/session-meta.json" > "$vl/m" && mv "$vl/m" "$vl/session-meta.json"
  echo '{"version":1,"concepts":[{"name":"express-routing","label":"Express routing","status":"shaky","sessions":2,"last_seen":"2026-10-16","last_quizzed":"2026-10-16","files":["src/app.js"]},"junk",{"name":"old","label":"Old concept"}]}' > "$vl/knowledge.json"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --json > "$BATS_TEST_TMPDIR/out" 2> "$BATS_TEST_TMPDIR/err"
  grep -q "Session briefing:" "$BATS_TEST_TMPDIR/err"
  local output; output="$(cat "$BATS_TEST_TMPDIR/out")"
  slug="2026-10-16-$(basename "$TEST_PROJECT_DIR" | tr '[:upper:]' '[:lower:]')-learn-test"
  # stdout is the stored facts and nothing else.
  [ "$(jq -c . <<<"$output")" = "$(jq -c . "$vl/briefing/sessions/$slug.json")" ]
  [ "$(jq -r '[.schema_version, .slug, .goal] | @tsv' <<<"$output")" = "$(printf '1\t%s\tBuild an Express API with two routes and a test for each' "$slug")" ]
  diff <(jq -S . "$VIBE_LEARN_DIR/tests/fixtures/briefing-facts.json") \
    <(jq -S 'del(.generated_at) | .project = "proj" | .slug = "SLUG"' <<<"$output")
}

@test "untrusted text from the log, ledger, summary, and diff is escaped on every page" {
  local x='<img src=x onerror=alert(1)></script><script>alert(2)</script><!--'
  local vl="$TEST_PROJECT_DIR/.vibe-learn" page
  mkdir -p "$vl"
  echo '{"session_id":"xss","started_at":"2026-10-16T09:00:00Z"}' > "$vl/session-meta.json"
  jq -nc --arg x "$x" '
    {event: "user_prompt", prompt: ("Build the widget service with tests " + $x)},
    {event: "tool_use", tool: "Write", file: ("src/" + $x + ".js"), action: "created"},
    {event: "tool_use", tool: "Edit", file: "src/a.js", action: $x},
    {event: "tool_use", tool: "Bash", command: ("npm test " + $x), action: "ran", context: {exit_code: 1}}' > "$vl/session-log.jsonl"
  jq -n --arg x "$x" '{version: 1, concepts: [{name: "c", label: $x, status: $x, sessions: 2, last_quizzed: $x}]}' > "$vl/knowledge.json"
  printf 'Summary %s\n' "$x" > "$vl/pause-summary.txt"
  echo xss > "$vl/pause-summary.session"
  git -C "$TEST_PROJECT_DIR" init -q
  printf 'old\n' > "$TEST_PROJECT_DIR/tracked.txt"
  git -C "$TEST_PROJECT_DIR" add tracked.txt
  printf '%s\n' "$x" > "$TEST_PROJECT_DIR/tracked.txt"

  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]
  page="$(session_file_for_test_project)"
  for f in "$page" "$vl/briefing/index.html"; do
    refute_grep '<img src=x' "$f"
    refute_grep '<!--' "$f"
    refute_grep '<script>alert' "$f"
    [ "$(grep -c '<script>' "$f")" -eq "$(grep -c '</script>' "$f")" ]
  done
  grep -q 'Build the widget service with tests &lt;img src=x' "$page"
  grep -q 'Build the widget service with tests &lt;img src=x' "$vl/briefing/index.html"
  # The copy buttons' JSON still parses back to the original text.
  sed -n 's/^    const packText = \(.*\);$/\1/p' "$page" | jq -r . | grep -qF "$x"
  sed -n 's/^    const diffText = \(.*\);$/\1/p' "$page" | jq -r . | grep -qF "$x"
}

# --- The three questions (S8) -------------------------------------------------

first_screen() { sed '/<details id="full-record">/q' "$(session_file_for_test_project)"; }

@test "the page answers what was built, what to understand, and what broke above a collapsed full record" {
  write_learning_session
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  local page top="$BATS_TEST_TMPDIR/top.html"
  page="$(session_file_for_test_project)"
  first_screen > "$top"

  grep -q '<blockquote class="ask">Build an Express API with two routes and a test for each</blockquote>' "$top"
  grep -q 'Turn 2 · the first substantial request' "$top"
  grep -q 'What to understand' "$top"
  grep -q '<details id="full-record">' "$top"
  # Learning turns stay out of the three questions.
  refute_grep 'vibe-learn:digest' "$top"
  refute_grep 'digests' "$top"
  # The open failure leads; the fixed one shows its fix.
  [ "$(grep -o 'class="break [a-z]*"' "$top" | tr '\n' ' ')" = 'class="break open" class="break fixed" ' ]
  grep -q '<code>npm run lint</code> failed (exit 1) · turn 5</div><div class="fix">→ still failing' "$top"
  grep -q '<code>npm test</code> failed (exit 1) · turn 2</div><div class="fix">→ fixed in turn 3 by <code>npm test</code>' "$top"
  grep -q '4 work turns · 2 files · 2 failed commands, 1 still failing' "$top"
  # The old sections live inside the record, which starts closed; one stylesheet.
  sed -n '/<details id="full-record">/,/<\/details>/p' "$page" | grep -q 'Session Timeline'
  refute_grep '<details id="full-record" open' "$page"
  [ "$(grep -c '<style' "$page")" -eq 1 ]
  grep -q 'Show learning turns (5)' "$page"
  grep -q 'ol.timeline:not(.show-learning) li\[data-learning\]{display:none;}' "$page"
}

@test "What to understand links ledger concepts to the session's files, else shows concepts seen that day" {
  write_learning_session
  local vl="$TEST_PROJECT_DIR/.vibe-learn"
  jq -n '{version: 1, concepts: [
    {name: "routing", label: "Express routing", status: "shaky", last_seen: "2026-10-01", last_quizzed: "2026-10-01", files: ["src/app.js", "src/other.js"]},
    {name: "testing", label: "Supertest", status: "new", last_seen: "2026-10-16", files: ["test/app.test.js"]},
    {name: "elsewhere", label: "Unrelated", status: "solid", last_seen: "2026-10-16", files: ["lib/x.js"]}]}' > "$vl/knowledge.json"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  local top="$BATS_TEST_TMPDIR/top.html"
  first_screen > "$top"
  grep -q '<strong>Express routing</strong><span class="chip status-shaky">shaky</span></div><div class="concept-files">in <a href="../../../src/app.js"><code>src/app.js</code></a></div>' "$top"
  grep -q '<div class="concept-files">in <a href="../../../test/app.test.js"><code>test/app.test.js</code></a></div><div class="concept-meta">not quizzed yet' "$top"
  refute_grep 'Unrelated' "$top"
  refute_grep 'src/other.js' "$top"

  # No concept names a session file: fall back to concepts seen on the session date.
  jq -n '{version: 1, concepts: [
    {name: "a", label: "Seen that day", status: "new", last_seen: "2026-10-16"},
    {name: "b", label: "Seen another day", status: "new", last_seen: "2026-09-01"}]}' > "$vl/knowledge.json"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  first_screen > "$top"
  grep -q 'seen on 2026-10-16. None are linked' "$top"
  grep -q '<strong>Seen that day</strong>' "$top"
  refute_grep 'Seen another day' "$top"

  rm "$vl/knowledge.json"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  first_screen | grep -q 'No knowledge-ledger concepts are linked to this session yet'
}

@test "file links are URL-encoded and paths outside the project are not linked" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  printf '%s\n' '{"event":"user_prompt","prompt":"Build the strange file names feature"}' \
    '{"event":"tool_use","tool":"Write","file":"src/a b&c?.js","action":"created"}' \
    '{"event":"tool_use","tool":"Write","file":"/etc/outside.conf","action":"created"}' \
    '{"event":"tool_use","tool":"Write","file":"src/../../up.txt","action":"created"}' \
    '{"event":"tool_use","tool":"Write","file":"src/..","action":"created"}' \
    '{"event":"tool_use","tool":"Write","file":"..","action":"created"}' > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  local page; page="$(session_file_for_test_project)"
  grep -q '<a href="../../../src/a%20b%26c%3F.js"><code>src/a b&amp;c?.js</code></a>' "$page"
  grep -q '<li><code>/etc/outside.conf</code>' "$page"
  # A ".." segment anywhere climbs out of the project: shown, never linked.
  grep -q '<li><code>src/../../up.txt</code>' "$page"
  grep -q '<li><code>src/..</code>' "$page"
  grep -q '<li><code>..</code>' "$page"
  refute_grep -F 'href="../../../src/..' "$page"
  refute_grep -F 'href="../../../.."' "$page"
}

@test "failures of one command with different exit codes are reported separately" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  printf '%s\n' '{"event":"user_prompt","prompt":"Make the build pass on every target please"}' \
    '{"event":"tool_use","tool":"Bash","command":"make test","action":"ran","context":{"exit_code":1}}' \
    '{"event":"tool_use","tool":"Bash","command":"make test","action":"ran","context":{"exit_code":2}}' \
    '{"event":"tool_use","tool":"Bash","command":"make test","action":"ran","context":{"exit_code":0}}' \
    > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  local top="$BATS_TEST_TMPDIR/top.html" pack
  first_screen > "$top"
  pack="$(pack_file_for_test_project)"
  grep -q '<code>make test</code> failed (exit 1) · turn 1' "$top"
  grep -q '<code>make test</code> failed (exit 2) · turn 1' "$top"
  refute_grep 'failed 2×' "$top"
  grep -qx '`make test` failed once with exit 1 (turn 1) and passed in turn 1.' "$pack"
  grep -qx '`make test` failed once with exit 2 (turn 1) and passed in turn 1.' "$pack"
}

@test "What broke shows at most five groups and points to the rest" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  {
    echo '{"event":"user_prompt","prompt":"Build seven tools and run each one"}'
    for i in 1 2 3 4 5 6 7; do
      printf '{"event":"tool_use","tool":"Bash","command":"tool%s --check","action":"ran","context":{"exit_code":2}}\n' "$i"
    done
  } > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  local top="$BATS_TEST_TMPDIR/top.html"
  first_screen > "$top"
  [ "$(grep -o 'class="break open"' "$top" | wc -l | tr -d ' ')" -eq 5 ]
  grep -q '2 more in the <a href="#commands">command log</a>' "$top"
  grep -q 'tool1 --check' "$top"
  refute_grep 'tool6 --check' "$top"
}

@test "every briefing page follows the system dark mode" {
  write_learning_session
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  local f
  for f in "$(session_file_for_test_project)" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html" "$SCRIPTS_DIR/lib/briefing-health.html"; do
    grep -q '@media (prefers-color-scheme: dark)' "$f"
    grep -q 'color-scheme:light dark' "$f"
  done
}

# --- The NotebookLM pack as prose (S9) ----------------------------------------

@test "the pack tells the session as prose: the ask, the files, and each failure with its fix" {
  write_learning_session
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  local pack; pack="$(pack_file_for_test_project)"
  grep -q '^You asked: "Build an Express API with two routes and a test for each" (turn 2). Later you asked "fix the failing test" and "add a /health route".' "$pack"
  grep -q 'The agent created 2 files, `src/app.js` and `test/app.test.js`; edited 1 file, `src/app.js`. It ran 4 commands, and 2 of them failed.' "$pack"
  grep -qx '| `src/app.js` | source | created, edited 2 times |' "$pack"
  grep -qx '`npm test` failed once with exit 1 (turn 2) and passed in turn 3.' "$pack"
  grep -qx '`npm run lint` failed once with exit 1 (turn 5). It still fails: nothing later in the session ran it successfully.' "$pack"
  grep -q 'What does the command that still fails mean' "$pack"
  refute_grep 'ls .vibe-learn/digests' "$pack"
}

@test "the pack shows a multi-line command as its first line, never its body" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  jq -nc '{event: "user_prompt", prompt: "Write the config file and check it twice"},
    {event: "tool_use", tool: "Bash", command: "cat > app.conf <<'"'"'EOF'"'"'\nport = 8080\nEOF", action: "ran", context: {exit_code: 1}},
    {event: "tool_use", tool: "Bash", command: "cat > app.conf <<'"'"'EOF'"'"'\nport = 8080\nEOF", action: "ran", context: {exit_code: 0}}' \
    > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  local pack; pack="$(pack_file_for_test_project)"
  grep -qF "\`cat > app.conf <<'EOF'\` (+2 lines) failed once with exit 1 (turn 1) and passed in turn 1." "$pack"
  # Outside code fences no line is a heredoc body or terminator.
  [ -z "$(awk '/^(```|~~~~)/ { fence = !fence; next } !fence && (/^EOF$/ || /^port = /)' "$pack")" ]
}

@test "the pack never follows an untracked symlink out of the project" {
  local vl="$TEST_PROJECT_DIR/.vibe-learn" outside="$BATS_TEST_TMPDIR/outside"
  mkdir -p "$vl" "$outside" "$TEST_PROJECT_DIR/src"
  printf 'LINKED_SECRET\n' > "$outside/secret.txt"
  printf 'export const ok = "INSIDE_BODY";\n' > "$TEST_PROJECT_DIR/src/ok.js"
  git -C "$TEST_PROJECT_DIR" init -q
  printf '.vibe-learn/\n' > "$TEST_PROJECT_DIR/.gitignore"
  ln -s "$outside" "$TEST_PROJECT_DIR/link"
  ln -s "$outside/secret.txt" "$TEST_PROJECT_DIR/src/alias.txt"
  printf '%s\n' '{"event":"user_prompt","prompt":"Read the linked config and add the ok module"}' \
    '{"event":"tool_use","tool":"Write","file":"link/secret.txt","action":"edited"}' \
    '{"event":"tool_use","tool":"Write","file":"src/alias.txt","action":"edited"}' \
    '{"event":"tool_use","tool":"Write","file":"src/ok.js","action":"created"}' > "$vl/session-log.jsonl"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  local pack; pack="$(pack_file_for_test_project)"
  grep -qF '+export const ok = "INSIDE_BODY";' "$pack"
  refute_grep 'LINKED_SECRET' "$pack"
  refute_grep 'LINKED_SECRET' "$(session_file_for_test_project)"
}

@test "the pack and page show files git does not track yet, but never ignored ones" {
  local vl="$TEST_PROJECT_DIR/.vibe-learn"
  mkdir -p "$vl" "$TEST_PROJECT_DIR/src"
  git -C "$TEST_PROJECT_DIR" init -q
  printf '.env\n.vibe-learn/\n' > "$TEST_PROJECT_DIR/.gitignore"
  printf 'export const beta = () => "BETA_BODY";\n' > "$TEST_PROJECT_DIR/src/beta.js"
  # Written by a shell command, then edited: logged only as an edit.
  printf 'export const gamma = "GAMMA_BODY";\n' > "$TEST_PROJECT_DIR/src/gamma.js"
  printf 'TOKEN=IGNORED_SECRET\n' > "$TEST_PROJECT_DIR/.env"
  # A path that climbs out of the project through src/.. is not the project's.
  local outside; outside="$(basename "$TEST_PROJECT_DIR").outside"
  printf 'OUTSIDE_SECRET\n' > "$TEST_PROJECT_DIR/../$outside"
  printf '%s\n' '{"event":"user_prompt","prompt":"Add the beta module and its env file"}' \
    "{\"event\":\"tool_use\",\"tool\":\"Write\",\"file\":\"$TEST_PROJECT_DIR/src/beta.js\",\"action\":\"created\"}" \
    '{"event":"tool_use","tool":"Write","file":".env","action":"created"}' \
    '{"event":"tool_use","tool":"Edit","file":"src/gamma.js","action":"edited"}' \
    "{\"event\":\"tool_use\",\"tool\":\"Write\",\"file\":\"src/../../$outside\",\"action\":\"created\"}" \
    "{\"event\":\"tool_use\",\"tool\":\"Write\",\"file\":\"src/x\\n../$outside\",\"action\":\"created\"}" > "$vl/session-log.jsonl"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  rm "$TEST_PROJECT_DIR/../$outside"
  local pack; pack="$(pack_file_for_test_project)"
  refute_grep 'OUTSIDE_SECRET' "$pack"
  grep -qx '+++ b/src/beta.js' "$pack"
  grep -qF '+export const beta = () => "BETA_BODY";' "$pack"
  grep -qF '+export const gamma = "GAMMA_BODY";' "$pack"
  grep -q 'BETA_BODY' "$(session_file_for_test_project)"
  refute_grep 'IGNORED_SECRET' "$pack"
  refute_grep 'IGNORED_SECRET' "$(session_file_for_test_project)"
}

# --- vibe-learn briefing --json (S17) -----------------------------------------

@test "briefing --json counts a learning turn the page cache skips, and fails with nothing on stdout when there is no session" {
  write_learning_session
  local vl="$TEST_PROJECT_DIR/.vibe-learn" before
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  before="$(jq '.turns.learning' "$vl"/briefing/sessions/*.json)"
  echo '{"event":"user_prompt","prompt":"/vibe-learn:quiz","kind":"learning"}' >> "$vl/session-log.jsonl"
  # The page stays cached: a learning turn changes nothing it shows.
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --if-stale | grep -q "up to date"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --json > "$BATS_TEST_TMPDIR/out" 2> "$BATS_TEST_TMPDIR/err"
  [ "$(jq -r .goal "$BATS_TEST_TMPDIR/out")" = "Build an Express API with two routes and a test for each" ]
  [ "$(jq '.turns.learning' "$BATS_TEST_TMPDIR/out")" -eq $((before + 1)) ]
  [ "$(jq '.turns.last_is_learning' "$BATS_TEST_TMPDIR/out")" = true ]
  [ "$(jq -r '.timeline[-1].text' "$BATS_TEST_TMPDIR/out")" = /vibe-learn:quiz ]

  : > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --json
  [ "$status" -eq 1 ]
  [ "$output" = "No session activity to brief yet." ]
}

@test "briefing --json --session prints an earlier session's facts by id" {
  write_learning_session
  local vl="$TEST_PROJECT_DIR/.vibe-learn"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  # The next session replaces the log and meta.
  echo '{"session_id":"next","started_at":"2026-10-17T09:00:00Z"}' > "$vl/session-meta.json"
  echo '{"event":"user_prompt","prompt":"Add the delete endpoint with its tests"}' > "$vl/session-log.jsonl"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null

  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --json --session learn-test
  [ "$status" -eq 0 ]
  [ "$(jq -r .goal <<<"$output")" = "Build an Express API with two routes and a test for each" ]
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --json --session=next
  [ "$(jq -r .goal <<<"$output")" = "Add the delete endpoint with its tests" ]
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --json --session nope
  [ "$status" -eq 1 ]
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --session learn-test
  [ "$status" -eq 1 ]

  # The index card of the earlier session shows its own goal and numbers.
  grep -q '<p class="card-goal">Build an Express API with two routes and a test for each</p>' "$vl/briefing/index.html"
  grep -q '<span class="tag danger">2 failed</span>' "$vl/briefing/index.html"
}

@test "vibe-learn briefing --json goes through the CLI" {
  write_learning_session
  run bash -c "bash '$SCRIPTS_DIR/cli.sh' briefing '$TEST_PROJECT_DIR' --json 2>/dev/null | jq -r .schema_version"
  [ "$output" = 1 ]
}
