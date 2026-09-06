#!/bin/bash
# social-preview.sh — static frame for docs/demo/social-preview.png (1280x640),
# rendered by social-preview.tape and uploaded as the GitHub social preview.

bold=$'\e[1m'; dim=$'\e[2m'; cyan=$'\e[36m'; green=$'\e[32m'; yellow=$'\e[33m'; reset=$'\e[0m'

printf '\e[?25l\n\n'
printf '  %svibe-learn%s  %s— learn as your AI coding assistant builds%s\n' "$bold" "$reset" "$dim" "$reset"
printf '  %sYou can outsource your thinking. You can'"'"'t outsource your understanding.%s\n' "$dim" "$reset"
printf '\n'
printf '  %s⏸ what just happened%s        %s❯%s /quiz\n' "$dim" "$reset" "$cyan" "$reset"
printf '  %s✦ Created src/middleware/auth.ts%s\n' "$dim" "$reset"
printf '  %s✦ Edited  src/routes/user.ts%s   %sQ1:%s Why middleware instead of per-route checks —\n' "$dim" "$reset" "$bold" "$reset"
printf '  %s✦ Ran     npm i jsonwebtoken%s       and what breaks when a new route is added?\n' "$dim" "$reset"
printf '\n'
printf '                                   %s> one place to enforce it; new routes are covered%s\n' "$cyan" "$reset"
printf '\n'
printf '                                   %sRight on the first half.%s %sMissed:%s only routes\n' "$green" "$reset" "$yellow" "$reset"
printf '                                   registered %safter%s app.use(auth) are protected.\n' "$bold" "$reset"
printf '\n'
printf '  %s/learn · /digest · /quiz · knowledge ledger · offline, bash + jq, no API keys%s\n' "$dim" "$reset"
printf '\n'
printf '  %sClaude Code · Codex · OpenCode · Grok · Cursor%s     %s/plugin install vibe-learn@vibe-learn%s\n' "$dim" "$reset" "$green" "$reset"

# Keep the shell prompt off-screen while the screenshot is taken.
sleep 6
