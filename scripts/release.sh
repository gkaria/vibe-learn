#!/bin/bash
# release.sh — Bump vibe-learn version across all files atomically,
# commit the change, and create a git tag.
#
# Usage:
#   bash scripts/release.sh [--dry-run] <new-version>
#
# --dry-run runs every check and lists the files it would bump, then exits
# without writing, committing, or tagging.

set -euo pipefail

usage() {
  echo "Usage: bash scripts/release.sh [--dry-run] <new-version>"
  echo "  e.g. bash scripts/release.sh 0.3.0"
  exit 1
}

DRY_RUN=false
NEW_VERSION=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -*) echo "ERROR: unknown option: $arg"; usage ;;
    *)
      if [ -n "$NEW_VERSION" ]; then
        echo "ERROR: expected one version, got '$NEW_VERSION' and '$arg'"
        usage
      fi
      NEW_VERSION="$arg"
      ;;
  esac
done
[ -n "$NEW_VERSION" ] || usage
# The version goes into file contents, a commit message and a tag name.
if ! printf '%s' "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'; then
  echo "ERROR: '$NEW_VERSION' is not a version like 1.2.3 or 1.2.3-rc.1"
  usage
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CURRENT_VERSION=$(cat "$REPO_ROOT/VERSION")

if [ "$CURRENT_VERSION" = "$NEW_VERSION" ]; then
  echo "Already at version $NEW_VERSION — nothing to do."
  exit 0
fi
# MAJOR.MINOR.PATCH must go up.
if ! awk -v a="$NEW_VERSION" -v b="$CURRENT_VERSION" 'BEGIN {
    split(a, x, /[.-]/); split(b, y, /[.-]/)
    for (i = 1; i <= 3; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 }
    exit 1 }'; then
  echo "ERROR: $NEW_VERSION is not newer than the current version $CURRENT_VERSION"
  exit 1
fi

echo "Bumping $CURRENT_VERSION → $NEW_VERSION"
echo ""

# --- Files that contain the version string ---
VERSION_FILES=(
  "VERSION"
  "scripts/setup.sh"
  ".release-please-manifest.json"
  ".claude-plugin/plugin.json"
  ".cursor-plugin/plugin.json"
)

# --- Verify all files contain the current version before touching anything ---
MISSING=()
for FILE in "${VERSION_FILES[@]}"; do
  if ! grep -qF "$CURRENT_VERSION" "$REPO_ROOT/$FILE" 2>/dev/null; then
    MISSING+=("$FILE")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "ERROR: Current version $CURRENT_VERSION not found in:"
  for F in "${MISSING[@]}"; do
    echo "  $F"
  done
  echo ""
  echo "Fix these files manually before releasing."
  exit 1
fi

# --- Also check for any other occurrences we might have missed ---
echo "Scanning for all occurrences of $CURRENT_VERSION..."
ALL_HITS=$(cd "$REPO_ROOT" && grep -rnF --include="*.sh" --include="*.json" --include="*.md" --include="VERSION" \
  "$CURRENT_VERSION" . 2>/dev/null | sed 's#^\./##' \
  | grep -vE '^(\.git/|.*/\.vibe-learn/|\.vibe-learn/|CHANGELOG\.md:|specs/|scripts/release\.sh:|CLAUDE\.md:)' || true)

# Every hit must be in a listed file; report each unlisted file:line.
UNLISTED=()
while IFS= read -r HIT; do
  [ -z "$HIT" ] && continue
  REL="${HIT%%:*}"
  KNOWN=false
  for F in "${VERSION_FILES[@]}"; do
    [ "$REL" = "$F" ] && KNOWN=true && break
  done
  [ "$KNOWN" = false ] && UNLISTED+=("$HIT")
done <<EOF
$ALL_HITS
EOF

if [ ${#UNLISTED[@]} -gt 0 ]; then
  echo "ERROR: Found $CURRENT_VERSION in files not listed in VERSION_FILES:"
  for H in "${UNLISTED[@]}"; do
    # file:line: text
    echo "  $(printf '%s' "$H" | cut -d: -f1,2)"
  done
  echo "  Add them to VERSION_FILES in scripts/release.sh, then re-run."
  exit 1
fi

if [ "$DRY_RUN" = true ]; then
  echo "Dry run: would bump"
  for FILE in "${VERSION_FILES[@]}"; do
    echo "  $FILE"
  done
  exit 0
fi

# --- Apply the bump (portable: works on macOS and Linux) ---
for FILE in "${VERSION_FILES[@]}"; do
  OLD="$CURRENT_VERSION" NEW="$NEW_VERSION" perl -pi -e 's/\Q$ENV{OLD}\E/$ENV{NEW}/g' "$REPO_ROOT/$FILE"
  echo "  ✓ $FILE"
done

echo ""

# --- Commit and tag (only version files, never unrelated staged changes) ---
cd "$REPO_ROOT"
git commit -m "chore: release v$NEW_VERSION" -- "${VERSION_FILES[@]}"
git tag -a "v$NEW_VERSION" -m "Release v$NEW_VERSION"

echo "✓ Committed version bump and created tag v$NEW_VERSION"
echo ""
echo "Push to publish:"
echo "  git push && git push --tags"
