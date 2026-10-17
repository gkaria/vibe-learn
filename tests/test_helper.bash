# test_helper.bash — shared setup/teardown for vibe-learn tests

SCRIPTS_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../scripts" && pwd)"
ADAPTERS_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../adapters" && pwd)"
VIBE_LEARN_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

setup() {
  # Create a temp directory to act as the project CWD
  TEST_PROJECT_DIR="$(mktemp -d)"
  export TEST_PROJECT_DIR
  # bootstrap.sh mirrors health rows into ~/.vibe-learn/health.jsonl; keep
  # tests away from the real one.
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
}

teardown() {
  # Clean up temp directory. Use || true so background processes that are still
  # writing to the directory (e.g. auto-generated dashboards) don't fail the test.
  rm -rf "$TEST_PROJECT_DIR" "$TEST_HOME" || true
}

# Helper: build a hook input JSON with cwd set to the test project
make_input() {
  local extra="$1"
  echo "{\"cwd\":\"$TEST_PROJECT_DIR\"${extra:+,$extra}}"
}

# A bare `! grep` fails a bats test only as its last line (set -e ignores a
# negated command); this fails wherever it is.
# Takes grep's options and arguments: refute_grep [-E] PATTERN FILE...
refute_grep() { if grep -q "$@"; then echo "unexpected match: grep $*"; return 1; fi; }

# The previous session's pause summary as a finished session leaves it: the
# summary, the file naming its session, and that session's meta.
seed_prior_summary() {
  local vl="$TEST_PROJECT_DIR/.vibe-learn"
  mkdir -p "$vl"
  printf '%s\n' "$1" > "$vl/pause-summary.txt"
  echo '{"session_id":"prior","started_at":"2026-01-01T00:00:00Z"}' > "$vl/session-meta.json"
  echo prior > "$vl/pause-summary.session"
}
