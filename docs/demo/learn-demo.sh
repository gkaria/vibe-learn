#!/bin/bash
# learn-demo.sh — scripted replay of the pause summary and a /learn answer,
# used by learn.tape to render docs/demo/learn.gif. Reproducible replay; the
# text is fixed. Set DEMO_FAST=1 to skip all delays (used by tests).

fast=${DEMO_FAST:-0}
pause() { [ "$fast" = 1 ] || sleep "$1"; }
say() { printf '%s\n' "$1"; pause 0.1; }

dim=$'\e[2m'; bold=$'\e[1m'; cyan=$'\e[36m'; reset=$'\e[0m'

say "${dim}⏸ vibe-learn — what just happened:${reset}"
say "${dim}Goal: add JWT auth middleware${reset}"
say ""
say "${dim}  ✦ Created src/middleware/auth.ts${reset}"
say "${dim}  ✦ Edited src/routes/user.ts${reset}"
say "${dim}  ✦ Ran: npm install jsonwebtoken${reset}"
say ""
pause 1.4
printf '%s❯%s /learn\n\n' "$cyan" "$reset"
pause 0.9
say "${bold}What just happened:${reset}"
say ""
say "• Added JWT auth middleware (src/middleware/auth.ts) — every request to a"
say "  protected route now passes a token check before reaching the handler"
say "• Wired it into the user routes (src/routes/user.ts), so /profile and"
say "  /settings require a valid token"
say "• Installed jsonwebtoken to sign and verify tokens"
say "• ${bold}Pattern worth knowing:${reset} middleware ordering — auth runs before the"
say "  route handlers, so handlers can safely assume req.user exists"
pause 3
