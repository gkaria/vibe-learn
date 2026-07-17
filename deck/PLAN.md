# vibe-deck — Plan & Status

> Continuation doc: everything a fresh session needs to pick this up.
> Last updated: 2026-07-17 (branch `deck-mvp`, M1 complete).

## What this is

vibe-deck turns an M5Stack **Cardputer-Adv** into a pocket, voice-first
control deck for AI assistants — the DIY answer to Work Louder's
[Codex Micro](https://worklouder.cc/codex-micro), plus something it
doesn't have: it talks back and teaches you (vibe-learn integration).

*vibe-learn helps you understand what your AI built; vibe-deck lets you
command it — and hear what you learned — from your pocket.*

Full usage/setup docs: [README.md](README.md). Original PRD lived in the
planning session; the essentials are all here.

## Product decisions (settled — don't relitigate)

1. **Mac-first gateway, not cloud.** Single daemon on the Mac; the device
   is a thin client over LAN HTTP + shared secret. The old
   cardputer-claude-os Cloudflare-Worker voice path stays untouched in
   that fork as legacy. (First-principles redesign was explicitly
   requested over extending the fork's architecture.)
2. **$0 marginal cost per command — hard requirement.** Local STT
   (parakeet-mlx), local TTS (macOS `say`), and subscription-backed CLIs
   as invisible plumbing: `claude -p` (Claude sub), `codex exec`
   (ChatGPT sub). **No API keys anywhere.** Paid paths only ever opt-in
   and labeled.
3. **Targets:** ① Claude chat ② ChatGPT chat (via codex, whose CLI UX
   the user dislikes but accepts as plumbing) ③ Learn (vibe-learn
   grounded, spoken) — and in M2: ④ Claude Code as the *only* coding
   agent (Codex coding = backlog).
4. **Monorepo folder, not a new repo.** `deck/` is self-contained inside
   vibe-learn; zero coupling to vibe-learn's `setup.sh`/VERSION/
   release-please/tests. Extractable later via `git mv`.
5. **Audio out lives on the Mac** (speakers/BT/AirPods via macOS
   routing). Device does chirps only — no audio streaming to ESP32.
6. **Physical consent for consequential actions** (M2): code-editing
   runs require the hold/tap-Y-3s gesture on-device showing the
   transcript + workdir first.

## Architecture

```
Cardputer-Adv ──WiFi/LAN HTTP + x-gateway-secret──► Mac gateway :8756
  (voice_center.mpy)                                 ├─ stt.py   parakeet-mlx, local
                                                     ├─ chat.py  claude -p / codex exec (session-resume memory)
                                                     ├─ learn.py .vibe-learn/session-log.jsonl grounding (haiku)
                                                     └─ tts.py   macOS say (serialized queue)
```

- Gateway runtime: `~/.vibe-deck/` (venv, `env` config, `state.json`,
  `chat/` scratch dirs — git-inited because codex requires a repo).
- launchd agent: `com.vibedeck.gateway` (installed, running).
- API: `POST /voice?target=claude|chatgpt|learn` (raw WAV →
  `{transcript,response,spoken}`) · `POST /text` · `POST /learn/digest` ·
  `POST /quiz/next` · `POST /quiz/answer` (WAV or `{answer}`) ·
  `POST /reset` (`{target?}`) · `GET /health`. All need `x-gateway-secret`.

## Status: M1 ✅ COMPLETE (gateway verified end-to-end via curl)

| Verified | Evidence |
|---|---|
| STT local, fast | 1.5 s transcript, no ffmpeg (soundfile decode in `stt.py`) |
| Claude chat + memory + reset | Paris follow-up test; reset forgets |
| ChatGPT chat + memory + reset | codeword test; reset forgets |
| Learn Q&A + digest | grounded in live session log, spoken prose, ~10–13 s |
| Quiz loop | question ← session log; graded right/wrong; accepts WAV answers |
| TTS | `spoken:true`, speaks via `say` |
| Auth | wrong secret → 401 |
| $0 | zero API keys in env/config |
| Daemon | launchd round-trip verified; RunAtLoad+KeepAlive set |
| Device app compiles | `voice_center.py` → 10.3 KB .mpy (heap-safe, pager precedent) |

Commits on `deck-mvp`: `c885393` (pristine fork imports) → `40e6534`
(M1 implementation) → `24aeec5` (CLI-flag fixes + haiku learn prompts).

## NOT done — immediate next steps

1. **Push the device app (blocked on hardware — Cardputer wasn't on USB):**
   ```bash
   cp deck/device/config.example.py deck/device/config.py
   # edit: GATEWAY_URL = "http://<Mac LAN IP>:8756"   (ipconfig getifaddr en0)
   #       GATEWAY_SECRET = value from ~/.vibe-deck/env
   python3 deck/scripts/push_app_mpy.py --port /dev/cu.usbmodem* \
       --config deck/device/config.py
   ```
   Then verify on hardware: launcher lists "voice center"; voice + text
   round-trips on targets 1/2; Learn D/G keys; OOM-free boot
   (`python3 deck/scripts/tail_serial.py --port ...`); note latency.
   Device keys: 1/2/3 or `,`/`/` targets · SPACE voice · T text · N new
   chat · D digest · **G quiz** (deviation from PRD's "Q": Q = back
   everywhere in the bundle) · `;`/`.` scroll · Q/ESC exit.
2. **Reboot-survival check** of the launchd agent (needs a real reboot).

## M2 (next milestone): ④ Claude Code coding target

Voice → transcript + target repo on LCD → **hold/tap-Y-3s physical
confirm** (port gesture from cardputer-claude-os
`buddy/device/apps/cardputer_mcp.py` confirm branches; ESC cancels with
zero side effects) → gateway runs `claude -p --permission-mode
acceptEdits` in an allowlisted workdir → summary (`exit 0 in 47s` +
~700 chars) back to LCD + chirp.

Gateway side: new `gateway/agents.py` — job table, `AGENT_WORKDIRS`
colon-list allowlist (empty ⇒ fail-closed disabled), `AGENT_TIMEOUT_S`
(300) kill, audit via `ConsentAuditLog` (already copied:
`gateway/audit.py`). New endpoints `POST /agent/submit`,
`GET /agent/status?job=` (device polls ~2 s). Env additions:
`AGENT_ENABLED`, `AGENT_WORKDIRS`, `AGENT_TIMEOUT_S`.

Verify: curl-only first ("create hello.txt" lands only in allowlisted
dir; non-allowlisted rejected; timeout kill; `AGENT_ENABLED=0` → 403;
audit lines written), then device flow incl. ESC-cancels-cleanly.

## Backlog (P2)

Quick-action keys (canned prompts) · model/effort cycling key · neural
TTS (Kokoro/mlx-audio drop-in at `tts.py::_speak_now`) · Codex as second
coding agent · remote access (cloudflared tunnel → gateway) · multi-job
dashboard · quiz results tracking · wake-word · LoRa/mesh experiments.

## Hard-won gotchas (do not rediscover)

- `claude -p --bare` **breaks subscription auth** ("Not logged in") on
  claude 2.1.x — don't use it.
- `claude -p` **exits 0 even on errors** — truth is `is_error` in its
  `--output-format json` output.
- `codex exec resume` **rejects `-C`/`-s`** — set cwd via subprocess and
  sandbox via `-c sandbox_mode="read-only"`. Session id is scraped from
  the run banner (uuid regex).
- All CLI spawns need `stdin=subprocess.DEVNULL` (codex reads piped stdin).
- parakeet-mlx's `load_audio` shells out to **ffmpeg** — bypassed via
  soundfile + `get_logmel(float32)` + `generate()`. Input to
  `get_logmel` must be **float32** (complex-STFT `mx.view` math breaks
  on bfloat16).
- Codex CLI was upgraded 0.142.3 → 0.144.5 (user's config pins
  `gpt-5.6-sol`, which needs the newer CLI).
- Device: mic is 16 kHz-locked; `recordWavFile` is the only reliable
  capture; apps >~25 KB source must ship as `.mpy`; plain-HTTP LAN
  avoids the mbedTLS internal-RAM OOM entirely.

## File map

```
deck/
├── PLAN.md                    ← this file
├── README.md                  setup + usage + API + troubleshooting
├── gateway/                   Mac daemon (FastAPI, venv at ~/.vibe-deck/venv)
│   ├── server.py  config.py  stt.py  chat.py  learn.py  tts.py
│   ├── audit.py               (pristine copy from fork; used in M2)
│   └── requirements.txt
├── device/
│   ├── voice_center.py        the Cardputer app (ship as .mpy)
│   ├── config.example.py      → copy to config.py (gitignored)
│   └── push_to_claude.py      (pristine fork base — reference only)
├── scripts/                   push_app_mpy.py · push.py · tail_serial.py · repl_run.py · mpy_repl.py
└── mac/                       com.vibedeck.gateway.plist · install_gateway.sh (+ fork originals)
```
