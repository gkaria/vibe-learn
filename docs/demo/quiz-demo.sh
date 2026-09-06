#!/bin/bash
# quiz-demo.sh — scripted replay of a /quiz round, used by quiz.tape to render
# docs/demo/quiz.gif. The transcript continues the JWT session shown in README.
# It is a replay, not a live model call: the text is fixed so the GIF is
# reproducible. Set DEMO_FAST=1 to skip all delays (used by tests).

fast=${DEMO_FAST:-0}

pause() { [ "$fast" = 1 ] || sleep "$1"; }

# Print a line as if streamed from the assistant.
say() {
  printf '%s\n' "$1"
  pause 0.18
}

# Type a user answer character by character.
type_answer() {
  printf '%s' "> "
  local text="$1" i
  for ((i = 0; i < ${#text}; i++)); do
    printf '%s' "${text:i:1}"
    pause 0.035
  done
  printf '\n'
}

dim=$'\e[2m'; bold=$'\e[1m'; cyan=$'\e[36m'; green=$'\e[32m'; yellow=$'\e[33m'; reset=$'\e[0m'

printf '%s❯%s /quiz\n\n' "$cyan" "$reset"
pause 0.8

say "${bold}vibe-learn quiz${reset} ${dim}— 2 questions from this session (JWT auth middleware)${reset}"
say ""
pause 0.4
say "${bold}Question 1 of 2:${reset} The auth check lives in middleware instead of inside"
say "each route handler. What does that buy us — and what's the risk when"
say "someone adds a new route later?"
say ""
pause 1.8
type_answer "no repeated checks in every handler, and new routes are protected automatically?"
say ""
pause 0.9
say "${green}Right on the first half${reset} — one enforcement point, no duplication."
say "${yellow}One nuance you missed:${reset} routes are only protected if they're registered"
say "${bold}after${reset} the middleware. A new route mounted above app.use(auth) skips the"
say "check entirely. That ordering is the thing to remember."
say ""
pause 4
say "${bold}Question 2 of 2:${reset} We installed jsonwebtoken instead of hand-rolling token"
say "signing. What does the library handle that's easy to get wrong?"
say ""
pause 1.8
type_answer "signature verification and expiry"
say ""
pause 0.9
say "${green}Yes.${reset} HMAC/RSA verification, the exp and nbf claims, and constant-time"
say "signature comparison — the last one is the classic hand-rolled mistake."
say ""
pause 2.5
say "${bold}Recap${reset}"
say "  ${green}Solid:${reset}   jwt-verification"
say "  ${yellow}Revisit:${reset} express-middleware-ordering — you had the what, not the when"
say ""
say "  ${green}✔${reset} 2 concepts recorded to .vibe-learn/knowledge.json"
say "  ${dim}Next session, /learn nudges you if middleware ordering resurfaces,${reset}"
say "  ${dim}and /quiz review re-asks until it's solid.${reset}"
pause 4
