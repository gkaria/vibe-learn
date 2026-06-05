#!/usr/bin/env bats

load test_helper

run_opencode_install() {
  bash "$ADAPTERS_DIR/opencode/install.sh" "$VIBE_LEARN_DIR" "$TEST_PROJECT_DIR"
}

run_opencode_global_install() {
  HOME="$1" bash "$ADAPTERS_DIR/opencode/install.sh" --global "$VIBE_LEARN_DIR"
}

@test "opencode install creates command files" {
  run_opencode_install

  [ -f "$TEST_PROJECT_DIR/.opencode/commands/learn.md" ]
  [ -f "$TEST_PROJECT_DIR/.opencode/commands/digest.md" ]
}

@test "opencode install creates plugin file with rendered install path" {
  run_opencode_install

  [ -f "$TEST_PROJECT_DIR/.opencode/plugins/vibe-learn.js" ]
  grep -q "const VIBE_LEARN_DIR = \"$VIBE_LEARN_DIR\"" "$TEST_PROJECT_DIR/.opencode/plugins/vibe-learn.js"
  grep -q 'runScript("observe.sh"' "$TEST_PROJECT_DIR/.opencode/plugins/vibe-learn.js"
  grep -q 'recentlyLoggedFile' "$TEST_PROJECT_DIR/.opencode/plugins/vibe-learn.js"
  ! grep -q "INSTALL_DIR_PLACEHOLDER" "$TEST_PROJECT_DIR/.opencode/plugins/vibe-learn.js"
}

@test "opencode plugin bridges core session tool file and idle events" {
  local install_dir="$TEST_PROJECT_DIR/install"
  local target_dir="$TEST_PROJECT_DIR/project"
  local calls_file="$TEST_PROJECT_DIR/plugin-calls.jsonl"
  local plugin_module="$TEST_PROJECT_DIR/vibe-learn-plugin.mjs"
  local runner="$TEST_PROJECT_DIR/run-plugin.mjs"

  mkdir -p "$install_dir/adapters" "$install_dir/scripts" "$target_dir"
  cp -R "$ADAPTERS_DIR/opencode" "$install_dir/adapters/opencode"

  for script in bootstrap observe pause-summary; do
    cat > "$install_dir/scripts/$script.sh" <<'SH'
#!/bin/bash
set -euo pipefail
printf '%s\t%s\n' "$(basename "$0")" "$(cat)" >> "$VIBE_LEARN_TEST_CALLS"
SH
    chmod +x "$install_dir/scripts/$script.sh"
  done

  bash "$ADAPTERS_DIR/opencode/install.sh" "$install_dir" "$target_dir"
  cp "$target_dir/.opencode/plugins/vibe-learn.js" "$plugin_module"

  cat > "$runner" <<'JS'
import { pathToFileURL } from "node:url";

const targetDir = process.argv[2];
const pluginPath = process.argv[3];
const { server } = await import(pathToFileURL(pluginPath).href);
const hooks = await server({ directory: targetDir, worktree: targetDir });

// session.created — dispatched via the event hook
await hooks.event({ event: { type: "session.created", properties: { info: { id: "open-session" } } } });

// tool.execute.after — bash (args in input, exit code in output.metadata)
await hooks["tool.execute.after"](
  { tool: "bash", args: { command: "npm test" } },
  { metadata: { exitCode: 2 } }
);

// tool.execute.after — write
await hooks["tool.execute.after"](
  { tool: "write", args: { filePath: "src/created.js" } },
  {}
);

// file.edited — via event hook; src/created.js should be deduplicated (just written above)
await hooks.event({ event: { type: "file.edited", properties: { file: "src/created.js" } } });

// file.edited — via event hook; new file, should not be deduplicated
await hooks.event({ event: { type: "file.edited", properties: { file: "src/edited.js" } } });

// session.idle — via event hook
await hooks.event({ event: { type: "session.idle", properties: { sessionID: "open-session" } } });
JS

  VIBE_LEARN_TEST_CALLS="$calls_file" node "$runner" "$target_dir" "$plugin_module"

  grep -q '^bootstrap.sh' "$calls_file"
  grep -q '^pause-summary.sh' "$calls_file"
  grep -q '"session_id":"open-session"' "$calls_file"
  grep -q '"tool_name":"Bash"' "$calls_file"
  grep -q '"command":"npm test"' "$calls_file"
  grep -q '"exit_code":2' "$calls_file"
  grep -q '"tool_name":"Write"' "$calls_file"
  grep -q '"file_path":"src/created.js"' "$calls_file"
  grep -q '"tool_name":"Edit"' "$calls_file"
  grep -q '"file_path":"src/edited.js"' "$calls_file"

  local created_count
  created_count="$(grep -c '"file_path":"src/created.js"' "$calls_file")"
  [ "$created_count" -eq 1 ]
}

@test "opencode install renders paths containing sed replacement characters" {
  local special_dir="$TEST_PROJECT_DIR/vibe & learn|root"
  local target_dir="$TEST_PROJECT_DIR/project"

  mkdir -p "$special_dir/adapters" "$special_dir/scripts" "$target_dir"
  cp -R "$ADAPTERS_DIR/opencode" "$special_dir/adapters/opencode"
  cp "$SCRIPTS_DIR/observe.sh" "$special_dir/scripts/observe.sh"

  bash "$ADAPTERS_DIR/opencode/install.sh" "$special_dir" "$target_dir"

  grep -Fq "const VIBE_LEARN_DIR = \"$special_dir\"" "$target_dir/.opencode/plugins/vibe-learn.js"
}

@test "opencode global install writes to ~/.config/opencode" {
  local fake_home
  fake_home="$(mktemp -d)"

  run_opencode_global_install "$fake_home"

  [ -f "$fake_home/.config/opencode/commands/learn.md" ]
  [ -f "$fake_home/.config/opencode/commands/digest.md" ]
  [ -f "$fake_home/.config/opencode/plugins/vibe-learn.js" ]

  rm -rf "$fake_home"
}

@test "opencode install creates .gitignore with .vibe-learn entry" {
  run_opencode_install

  [ -f "$TEST_PROJECT_DIR/.gitignore" ]
  grep -q '\.vibe-learn/' "$TEST_PROJECT_DIR/.gitignore"
}

@test "opencode install is idempotent" {
  run_opencode_install
  run_opencode_install

  [ -f "$TEST_PROJECT_DIR/.opencode/plugins/vibe-learn.js" ]
  local count
  count=$(grep -c '\.vibe-learn' "$TEST_PROJECT_DIR/.gitignore")
  [ "$count" -eq 1 ]
}
