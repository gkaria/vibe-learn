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

1. Run this block in a shell, unchanged except for the path and the commands
   line:

   cd '/path/to/project' || exit 1
   commands=keep   # set to drop if you put secrets on command lines
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
   done | jq -s --argjson capture "$capture" --arg commands "$commands" 'map(del(.diff, .knowledge)
     | if $capture then . else del(.goal, .pause_summary, .last_turn.prompt)
       | .timeline |= map(select(.kind != "prompt")) end
     | if $commands == "drop" then del(.commands, .failures[].command, .failures[].fixed_by.command, .last_turn.commands, .pause_summary)
       | .timeline |= map(select(.kind != "command")) else . end)'
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

The bot's model reads the shell block's output: for each session, the file paths it changed, the first line of each command it ran with its exit code, the failures and the commands that fixed them, counts, and the ledger concepts for that session; plus the due concepts. That output goes to the bot's model provider under the bot's terms. The block always removes the diff and the full ledger.

`capture_prompts: false` covers prompt text only. The block then also removes `goal`, `pause_summary`, `last_turn.prompt`, and the prompt entries of `timeline`, including prompts an older log captured before you turned capture off. It does not remove commands: the digest needs them to explain what broke, and a command can contain text from your prompt or a secret passed on the command line. If that is a concern, set `commands=drop`. The block then also removes every facts field that can hold a command line: `commands`, `failures[].command`, `failures[].fixed_by.command`, `last_turn.commands`, the command entries of `timeline`, and `pause_summary` (it lists failing and last-turn commands). The digest then reports failures by count and turn only. A command you type into a prompt is prompt text, covered by `capture_prompts`, not by `commands=drop`.

The chat message holds the project name, counts, digest paths, one concept label and question, and the goal only when `capture_prompts` is on. The prompt tells the bot to leave command text, diff text, and file contents out of the message; that part is an instruction, not a filter.
