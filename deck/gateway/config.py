"""vibe-deck gateway configuration.

Settings load from ~/.vibe-deck/env (KEY=VALUE lines, # comments), with
process environment variables taking precedence. GATEWAY_SECRET is
required — the gateway refuses to start without it (fail closed).
"""

from __future__ import annotations

import os
from pathlib import Path

HOME = Path.home()
STATE_DIR = HOME / ".vibe-deck"
ENV_FILE = STATE_DIR / "env"

DEFAULTS = {
    "GATEWAY_HOST": "0.0.0.0",
    "GATEWAY_PORT": "8756",
    "STT_BACKEND": "parakeet",  # parakeet | mlx_whisper
    "STT_MODEL": "mlx-community/parakeet-tdt-0.6b-v3",
    "TTS_ENABLED": "1",
    "TTS_VOICE": "",  # empty = system default voice
    "TTS_RATE": "200",
    "LEARN_REPOS": str(HOME / "Development" / "GitHubForks" / "*"),
    "CHAT_TIMEOUT_S": "180",
    "CLAUDE_BIN": "claude",
    "CODEX_BIN": "codex",
    "REPLY_STYLE": (
        "Answer in plain spoken prose suitable for being read aloud: "
        "concise, under 120 words, no markdown, no code blocks unless asked."
    ),
}


def _read_env_file(path: Path) -> dict:
    values = {}
    if not path.exists():
        return values
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


class Config:
    def __init__(self):
        file_values = _read_env_file(ENV_FILE)
        self._values = {**DEFAULTS, **file_values, **{
            k: v for k, v in os.environ.items() if k in DEFAULTS or k == "GATEWAY_SECRET"
        }}
        if "GATEWAY_SECRET" in file_values and "GATEWAY_SECRET" not in os.environ:
            self._values["GATEWAY_SECRET"] = file_values["GATEWAY_SECRET"]

    def get(self, key: str, default: str | None = None) -> str | None:
        return self._values.get(key, default)

    def require(self, key: str) -> str:
        value = self._values.get(key)
        if not value:
            raise SystemExit(
                f"{key} is not set. Add it to {ENV_FILE} (see deck/README.md)."
            )
        return value

    @property
    def secret(self) -> str:
        return self.require("GATEWAY_SECRET")


def load() -> Config:
    STATE_DIR.mkdir(exist_ok=True)
    return Config()
