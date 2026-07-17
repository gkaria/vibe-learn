# vibe-deck

**A pocket, voice-first control deck for your AI assistants** — hold a key
on an M5Stack Cardputer-Adv, speak, and route the prompt to Claude,
ChatGPT, or vibe-learn's Learn mode. Replies land on the 240×135 LCD;
Learn-mode answers are also **spoken aloud** through your Mac (or
whatever Bluetooth speaker / AirPods it's routed to).

*vibe-learn helps you understand what your AI built; vibe-deck lets you
command it — and hear what you learned — from your pocket.*

Inspired by Work Louder's [Codex Micro](https://worklouder.cc/codex-micro),
but DIY, multi-assistant, and **$0 per command**.

## Cost model — $0 marginal, by design

| Piece | Runs | Cost |
|---|---|---|
| Speech-to-text | NVIDIA Parakeet V3 locally via MLX on the Mac | $0 |
| Claude chat | `claude -p` headless (your Claude subscription) | $0 |
| ChatGPT chat | `codex exec` headless (your ChatGPT subscription) | $0 |
| Learn / digest / quiz | `claude -p` over vibe-learn session logs | $0 |
| Text-to-speech | macOS `say` | $0 |

No API keys are configured anywhere. The only budget is your
subscriptions' rate-limit windows, shared with your normal CLI use.

## Architecture

```
Cardputer-Adv ──WiFi/LAN HTTP + x-gateway-secret──► Mac gateway :8756
                                                     ├─ stt.py   parakeet-mlx (local)
                                                     ├─ chat.py  claude -p / codex exec
                                                     ├─ learn.py .vibe-learn session logs
                                                     └─ tts.py   macOS say
```

The Mac is the brain; the device is thin (a URL + a shared secret).
Audio never leaves your LAN.

## Setup

### 1. Mac gateway

```bash
python3 -m venv ~/.vibe-deck/venv
~/.vibe-deck/venv/bin/pip install -r deck/gateway/requirements.txt

mkdir -p ~/.vibe-deck
echo "GATEWAY_SECRET=$(openssl rand -hex 16)" > ~/.vibe-deck/env
chmod 600 ~/.vibe-deck/env

# foreground first run (downloads the ~2 GB STT model once):
cd deck && ~/.vibe-deck/venv/bin/uvicorn gateway.server:app --host 0.0.0.0 --port 8756

# then install as a launchd daemon (survives reboot):
deck/mac/install_gateway.sh
```

Requirements: Apple Silicon, `claude` and `codex` CLIs signed in.

All settings live in `~/.vibe-deck/env` (see `gateway/config.py`
DEFAULTS for the full list): `STT_BACKEND`, `TTS_ENABLED`, `TTS_VOICE`,
`LEARN_REPOS` (colon-separated globs of repos vibe-learn observes),
`CHAT_TIMEOUT_S`, `REPLY_STYLE`.

### 2. Device (Cardputer-Adv)

Assumes the device already runs the
[cardputer-claude-os](https://github.com/gkaria/cardputer-claude-os)
launcher bundle (see its `m5-onboard` skill for first-time flashing).

```bash
cp deck/device/config.example.py deck/device/config.py
# edit: GATEWAY_URL = your Mac's LAN IP (ipconfig getifaddr en0), GATEWAY_SECRET

pip3 install --user --break-system-packages mpy-cross
python3 deck/scripts/push_app_mpy.py --port /dev/cu.usbmodem* \
    --config deck/device/config.py
```

The launcher auto-discovers `voice center` on next boot.

## Using it

| Key | Where | Does |
|---|---|---|
| `1` / `2` / `3` (or `,` `/`) | idle | switch target: Claude / ChatGPT / Learn |
| `SPACE` | idle | hold-ish: record 6 s of speech, send |
| `T` | chat targets | type instead of speak |
| `N` | chat targets | new chat (drops the CLI session) |
| `D` | Learn | spoken digest of the latest session |
| `G` | Learn | quiz round — question is spoken, answer by voice with `SPACE` |
| `;` / `.` | result | scroll |
| `Q` / `ESC` | anywhere | back to launcher |

Learn mode grounds every answer in the most recently active repo's
`.vibe-learn/session-log.jsonl` (override per request with the `repo`
param). The quiz is fully hands-free except two key presses: `G`, then
`SPACE` to answer.

## API (for scripting)

All requests need `x-gateway-secret`. `POST /voice?target=claude|chatgpt|learn`
(raw WAV → `{transcript, response, spoken}`) · `POST /text`
(`{prompt, target}`) · `POST /learn/digest` · `POST /quiz/next` ·
`POST /quiz/answer` (WAV or `{answer}`) · `POST /reset` (`{target?}`) ·
`GET /health`.

## Troubleshooting

- **Gateway logs:** `tail -f /tmp/vibe-deck.err.log` (launchd) or the
  uvicorn terminal.
- **Device serial:** `python3 deck/scripts/tail_serial.py --port /dev/cu.usbmodem*`
- **First reply is slow:** the STT model loads at gateway startup; chat
  replies are dominated by CLI spawn time (~2–5 s).
- **`codex` refuses in scratch dir:** the gateway `git init`s its chat
  scratch dirs automatically; delete `~/.vibe-deck/chat` to reset them.

## Roadmap (from the PRD)

M2: Claude Code as a coding target — voice → physical hold-Y confirm on
the device → sandboxed `claude -p` run in an allowlisted repo → summary
+ chirp. Backlog: quick-action keys, model/effort cycling, neural TTS
(Kokoro/mlx-audio), Codex coding, remote access via a tunnel, wake-word.

## Paid fast-path (optional, off by default)

The design goal is $0/command. If you ever want lower latency you can
add API-backed chat (Anthropic/OpenAI SDKs) — deliberately **not**
implemented; the CLI plumbing is the product.
