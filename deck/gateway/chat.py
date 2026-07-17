"""Subscription-backed chat targets.

Both targets run local CLIs headlessly as plumbing — no API keys, $0
marginal cost:

- claude:  `claude -p` (bills to the Claude subscription)
- chatgpt: `codex exec` (bills to the ChatGPT subscription)

Each target chats inside its own empty scratch directory under
~/.vibe-deck/chat/ so the agent has nothing to act on, and conversation
memory uses the CLI's native session resume. Session ids persist in
~/.vibe-deck/state.json; reset() drops them.
"""

from __future__ import annotations

import json
import re
import subprocess
import tempfile
import time
from pathlib import Path

from .config import STATE_DIR

STATE_FILE = STATE_DIR / "state.json"
CHAT_DIR = STATE_DIR / "chat"


def _load_state() -> dict:
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text())
        except ValueError:
            pass
    return {}


def _save_state(state: dict):
    STATE_FILE.write_text(json.dumps(state, indent=2))


def _scratch_dir(name: str) -> Path:
    d = CHAT_DIR / name
    if not (d / ".git").exists():
        d.mkdir(parents=True, exist_ok=True)
        # codex refuses to run outside a git repo; an empty one satisfies it
        subprocess.run(["git", "init", "-q", str(d)], check=False)
    return d


class ChatError(Exception):
    pass


class ClaudeChat:
    """Chat via `claude -p`, memory via --resume <session_id>."""

    name = "claude"

    def __init__(self, cfg):
        self.bin = cfg.get("CLAUDE_BIN")
        self.timeout = int(cfg.get("CHAT_TIMEOUT_S"))
        self.style = cfg.get("REPLY_STYLE")

    def ask(self, prompt: str) -> str:
        state = _load_state()
        session_id = state.get("claude_session")
        # No --bare: it breaks subscription auth on claude 2.1.x
        # ("Not logged in") — verified empirically.
        cmd = [
            self.bin, "-p", "--output-format", "json",
            "--append-system-prompt", self.style,
        ]
        if session_id:
            cmd += ["--resume", session_id]
        cmd.append(prompt)
        proc = subprocess.run(
            cmd, cwd=_scratch_dir("claude"), capture_output=True,
            text=True, timeout=self.timeout, stdin=subprocess.DEVNULL,
        )
        data = {}
        if proc.returncode == 0:
            try:
                data = json.loads(proc.stdout)
            except ValueError:
                pass
        # claude exits 0 even on errors — is_error in the JSON is the truth
        if proc.returncode != 0 or not data or data.get("is_error"):
            # a stale/deleted session id is the common failure; retry fresh
            if session_id:
                state.pop("claude_session", None)
                _save_state(state)
                return self.ask(prompt)
            detail = (data.get("result") or proc.stderr.strip())[:300]
            raise ChatError(detail or "claude failed")
        if data.get("session_id"):
            state["claude_session"] = data["session_id"]
            _save_state(state)
        return (data.get("result") or "").strip()

    def reset(self):
        state = _load_state()
        state.pop("claude_session", None)
        _save_state(state)


class ChatGPTChat:
    """Chat via `codex exec`, memory via `codex exec resume <session_id>`."""

    name = "chatgpt"

    def __init__(self, cfg):
        self.bin = cfg.get("CODEX_BIN")
        self.timeout = int(cfg.get("CHAT_TIMEOUT_S"))
        self.style = cfg.get("REPLY_STYLE")

    def ask(self, prompt: str) -> str:
        state = _load_state()
        session_id = state.get("chatgpt_session")
        styled = f"{prompt}\n\n({self.style})"
        with tempfile.NamedTemporaryFile(suffix=".txt", delete=False) as f:
            out_file = f.name
        # `exec resume` rejects -C/-s (they're exec-only flags), so the
        # workdir comes from subprocess cwd and the sandbox from a config
        # override, which both invocations accept.
        if session_id:
            cmd = [self.bin, "exec", "resume", session_id]
        else:
            cmd = [self.bin, "exec"]
        cmd += [
            "-c", 'sandbox_mode="read-only"',
            "--output-last-message", out_file, styled,
        ]
        proc = subprocess.run(
            cmd, cwd=_scratch_dir("chatgpt"), capture_output=True,
            text=True, timeout=self.timeout, stdin=subprocess.DEVNULL,
        )
        if proc.returncode != 0:
            if session_id:
                state.pop("chatgpt_session", None)
                _save_state(state)
                return self.ask(prompt)
            raise ChatError(proc.stderr.strip()[:300] or "codex failed")
        new_id = self._find_session_id(proc.stderr + proc.stdout)
        if new_id:
            state["chatgpt_session"] = new_id
            _save_state(state)
        reply = Path(out_file).read_text().strip()
        Path(out_file).unlink(missing_ok=True)
        if not reply:
            raise ChatError("codex returned an empty reply")
        return reply

    @staticmethod
    def _find_session_id(output: str) -> str | None:
        m = re.search(
            r"session[ _]?id:?\s*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-"
            r"[0-9a-f]{4}-[0-9a-f]{12})", output, re.IGNORECASE,
        )
        return m.group(1) if m else None

    def reset(self):
        state = _load_state()
        state.pop("chatgpt_session", None)
        _save_state(state)


def targets(cfg) -> dict:
    start = time.time()
    result = {t.name: t for t in (ClaudeChat(cfg), ChatGPTChat(cfg))}
    print(f"[chat] targets ready in {time.time() - start:.2f}s")
    return result
