# Routine: pre-release end-to-end check (maintainers)

Before each release a maintainer runs [`tests/e2e/run.sh`](../../tests/e2e/run.sh) by hand on the release branch. It drives real Claude Code sessions and needs a Claude credential, so it is not a CI job. This recipe is the same check written as a prompt, for a maintainer who asks their own agent to do it on their machine.

## By hand

```bash
git fetch origin
git worktree add --detach /tmp/vl-release origin/release-please--branches--main
export CLAUDE_CODE_OAUTH_TOKEN=...   # from `claude setup-token`, or set ANTHROPIC_API_KEY
tests/e2e/run.sh /tmp/vl-release
git worktree remove /tmp/vl-release
```

Run it from any checkout that has `tests/e2e/`. Release when the last line is `e2e: PASS`. On `e2e: FAIL`, the `FAIL` lines name each expectation that broke with the value it got, and the work directory it keeps holds the project, `claude.log`, the facts JSON, and the observed counts. A change that alters the counts on purpose updates `tests/e2e/golden/express-api.json` in the same PR.

## As a prompt

Paste this into an agent session on the maintainer's machine, with the credential already exported:

````text
Run the vibe-learn pre-release end-to-end check, then report the result on the
release PR.

1. In the vibe-learn repository, run:

   git fetch origin release-please--branches--main
   wt="$(mktemp -d)/vl-release"
   git worktree add --detach "$wt" FETCH_HEAD
   tests/e2e/run.sh "$wt" > /tmp/vl-e2e-result.txt 2>&1; echo "status $?"
   git worktree remove --force "$wt"

   If the fetch fails, there is no pending release PR: stop.

2. Comment on the release PR with only the result lines:

   grep -E '^(ok|FAIL|e2e:)' /tmp/vl-e2e-result.txt > /tmp/vl-e2e-comment.txt
   gh pr comment release-please--branches--main --body-file /tmp/vl-e2e-comment.txt

   Do not post claude.log or any other file from the work directory.

3. If the status was not 0, do not merge. Say which expectations failed.
````
