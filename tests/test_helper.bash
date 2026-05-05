# test_helper.bash — shared setup/teardown for vibe-learn tests

SCRIPTS_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../scripts" && pwd)"
ADAPTERS_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../adapters" && pwd)"
VIBE_LEARN_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

setup() {
  # Create a temp directory to act as the project CWD
  TEST_PROJECT_DIR="$(mktemp -d)"
  export TEST_PROJECT_DIR
}

teardown() {
  # Clean up temp directory
  rm -rf "$TEST_PROJECT_DIR"
}

# Helper: build a hook input JSON with cwd set to the test project
make_input() {
  local extra="$1"
  echo "{\"cwd\":\"$TEST_PROJECT_DIR\"${extra:+,$extra}}"
}
