#!/usr/bin/env python3
"""Talk to the vibe-deck gateway using the Mac's own microphone —
a stand-in for the Cardputer while it isn't flashed/connected.

    ~/.vibe-deck/venv/bin/python deck/scripts/talk.py                # ask Claude
    ~/.vibe-deck/venv/bin/python deck/scripts/talk.py -t chatgpt
    ~/.vibe-deck/venv/bin/python deck/scripts/talk.py -t learn      # answer is spoken
    ~/.vibe-deck/venv/bin/python deck/scripts/talk.py --quiz        # spoken quiz round

Records N seconds (default 6, like the device), sends the WAV to the
gateway, prints the transcript + reply. First run will trigger the macOS
microphone-permission prompt for your terminal.
"""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
import urllib.request
from pathlib import Path

RATE = 16000


def read_secret() -> str:
    env = Path.home() / ".vibe-deck" / "env"
    for line in env.read_text().splitlines():
        if line.startswith("GATEWAY_SECRET="):
            return line.split("=", 1)[1].strip()
    sys.exit(f"GATEWAY_SECRET not found in {env}")


def record(seconds: float) -> bytes:
    try:
        import sounddevice as sd
        import soundfile as sf
    except ImportError:
        sys.exit(
            "missing deps — run: ~/.vibe-deck/venv/bin/pip install sounddevice"
        )
    print(f"● recording {seconds:.0f}s — speak now...", flush=True)
    audio = sd.rec(int(seconds * RATE), samplerate=RATE, channels=1, dtype="int16")
    sd.wait()
    print("○ done, sending")
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        sf.write(f.name, audio, RATE, subtype="PCM_16")
        return Path(f.name).read_bytes()


def post(base: str, secret: str, path: str, body: bytes, timeout: int = 300) -> dict:
    req = urllib.request.Request(
        base + path, data=body, method="POST",
        headers={"x-gateway-secret": secret, "content-type": "audio/wav"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.load(resp)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("-t", "--target", default="claude",
                    choices=["claude", "chatgpt", "learn"])
    ap.add_argument("-s", "--seconds", type=float, default=6)
    ap.add_argument("--quiz", action="store_true",
                    help="quiz round: hear a question, then answer by voice")
    ap.add_argument("--base", default="http://127.0.0.1:8756")
    args = ap.parse_args()

    secret = read_secret()

    try:
        if args.quiz:
            q = post(args.base, secret, "/quiz/next", b"{}")
            print(f"\nQUIZ [{q.get('repo')}]: {q['response']}\n")
            wav = record(args.seconds)
            result = post(args.base, secret, "/quiz/answer", wav)
        else:
            wav = record(args.seconds)
            result = post(args.base, secret, f"/voice?target={args.target}", wav)
    except urllib.error.HTTPError as e:
        sys.exit(f"gateway error {e.code}: {e.read().decode()[:200]}")

    print(f"\nyou said: {result.get('transcript')}")
    print(f"\n[{args.target}{' · ' + result['repo'] if 'repo' in result else ''}]"
          f" {result.get('response')}")
    if result.get("spoken"):
        print("(also being spoken through your Mac's audio output)")


if __name__ == "__main__":
    main()
