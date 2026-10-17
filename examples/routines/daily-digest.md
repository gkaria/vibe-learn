# Routine: daily learning digest

A scheduled agent bot (Grok Bot, a Claude Code routine, or `claude -p` from cron) reads your latest session briefings, writes the digest `/digest` would have written, and quizzes you in chat on one concept that is due. See [docs/bots.md](../../docs/bots.md) for when to use it and [docs/privacy.md](../../docs/privacy.md#routines) for what it may read and send.

## Before you schedule it

- The bot must run shell commands on the machine that holds the project, with the `vibe-learn` CLI on its `PATH` (the curl installer puts it in `~/.local/bin`).
- Replace `/path/to/project` in the prompt with the project's absolute path. One routine per project.
- Start the bot in its own working directory, not in the project. If vibe-learn's hooks are installed for the bot's host, a bot session started in the project is logged there as a new session and rotates yours.
- Run it once a day, at a time you are not working: a session still in progress is digested as it stands, and the routine does not come back to it.

## Prompt

Paste this as the routine's prompt:

````text
You run the vibe-learn daily digest for one project. Work only from the output
of the shell block below. Do not open .vibe-learn/session-log*.jsonl,
.vibe-learn/pause-summary.txt, host transcripts, briefing HTML, or project files.

1. Run this block in a shell, unchanged except for the path:

   cd '/path/to/project' || exit 1
   since=$(date -d yesterday +%F 2>/dev/null || date -v-1d +%F)
   capture=true
   for f in "$HOME/.vibe-learn/config.json" .vibe-learn/config.json; do
     v=$(jq -r 'if .capture_prompts == false then "false" elif .capture_prompts == true then "true" else empty end' "$f" 2>/dev/null)
     [ -n "$v" ] && capture=$v
   done
   vibe-learn briefing --json >/dev/null 2>&1
   echo "SESSIONS"
   for f in .vibe-learn/briefing/sessions/*.json; do
     [ -f "$f" ] && [ ! -f ".vibe-learn/digests/$(basename "$f" .json)-routine.md" ] \
       && jq --arg since "$since" 'select(.date >= $since)' "$f" 2>/dev/null
   done | jq -s --argjson capture "$capture" 'map(del(.diff, .knowledge)
     | if $capture then . else del(.goal, .pause_summary, .last_turn.prompt)
       | .timeline |= map(select(.kind != "prompt")) end)'
   echo "DUE"
   vibe-learn knowledge due --days=14

   SESSIONS is a JSON array of session facts (fields in docs/briefing.md).
   DUE is a JSON array of ledger concepts due for review.

2. If both arrays are empty, stop. Send nothing.

3. For each session, write a digest with these sections, using only its JSON:
   "What Was Built" (from goal when present, files, and last_turn), "Key
   Decisions", "Patterns Used", and "Things to Study" (from concepts and
   failures). Save it as .vibe-learn/digests/<slug>-routine.md, where <slug>
   is the session's slug field. Never overwrite an existing file.

4. Send one chat message. For each session: the project, the goal only if the
   goal field is present and not null, the number of files changed, the number
   of failures and how many were fixed, and the digest's path. Never include
   command text, diff text, file contents, or prompt text from any other field.

5. If DUE is not empty, take its first concept with status "shaky", else its
   first concept. End the message with one recall question about it, built from
   its label and notes. Ask only one question per run.

6. When I answer, grade the answer in one or two sentences, then record it:

   vibe-learn knowledge record '<name>' --label='<label>' --status=solid

   or, when the answer was wrong or incomplete:

   vibe-learn knowledge record '<name>' --label='<label>' --status=shaky --notes='<what was missing>'

   Run it in the project directory. Inside single quotes, write a ' as '\''.
````

## What it sends

The chat message holds the project name, counts, digest paths, one concept label and question, and the goal only when `capture_prompts` is on. With `capture_prompts: false`, the shell block removes `goal`, `pause_summary`, `last_turn.prompt`, and the prompt entries of `timeline` before the bot sees the facts, so prompt text cannot reach the message even when an older log still holds some. The diff and the full ledger are removed in both cases.
