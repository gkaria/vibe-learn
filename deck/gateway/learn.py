"""Learn mode — spoken answers grounded in vibe-learn session data.

vibe-learn writes `.vibe-learn/session-log.jsonl` (turn-structured event
log) and `pause-summary.txt` into every repo it observes. This module
picks the most recently active of those repos, stuffs recent log context
into a `claude -p` prompt, and answers learn questions, digests, and quiz
rounds. Quiz state (the pending question) lives in state.json.
"""

from __future__ import annotations

import glob
import json
import subprocess
from pathlib import Path

from .chat import _load_state, _save_state, _scratch_dir, ChatError

MAX_LOG_CHARS = 12000
MAX_EVENTS = 120


def resolve_repo(cfg, override: str | None = None) -> Path | None:
    """Most recently active repo with vibe-learn data (or the override)."""
    if override:
        p = Path(override).expanduser()
        return p if (p / ".vibe-learn" / "session-log.jsonl").exists() else None
    best, best_mtime = None, 0.0
    for pattern in cfg.get("LEARN_REPOS").split(":"):
        for log in glob.glob(str(Path(pattern).expanduser() / ".vibe-learn" / "session-log.jsonl")):
            mtime = Path(log).stat().st_mtime
            if mtime > best_mtime:
                best, best_mtime = Path(log).parent.parent, mtime
    return best


def _session_context(repo: Path) -> str:
    """Recent session events + pause summary, trimmed to fit a prompt."""
    parts = [f"Repo: {repo.name}"]
    summary = repo / ".vibe-learn" / "pause-summary.txt"
    if summary.exists():
        parts.append("Latest pause summary:\n" + summary.read_text()[:1500])
    log = repo / ".vibe-learn" / "session-log.jsonl"
    lines = log.read_text().splitlines()[-MAX_EVENTS:]
    events = []
    for line in lines:
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if e.get("event") == "user_prompt":
            events.append(f"[turn {e.get('turn')}] USER: {e.get('prompt', '')[:200]}")
        elif e.get("event") == "tool_use":
            detail = e.get("command") or e.get("file") or ""
            events.append(f"  {e.get('action', 'did')} {e.get('tool', '')}: {str(detail)[:160]}")
    parts.append("Session events (most recent last):\n" + "\n".join(events))
    return "\n\n".join(parts)[:MAX_LOG_CHARS]


class Learn:
    def __init__(self, cfg):
        self.cfg = cfg
        self.bin = cfg.get("CLAUDE_BIN")
        self.timeout = int(cfg.get("CHAT_TIMEOUT_S"))

    def _claude(self, system: str, prompt: str) -> str:
        proc = subprocess.run(
            [self.bin, "-p", "--output-format", "text",
             "--append-system-prompt", system, prompt],
            cwd=_scratch_dir("learn"), capture_output=True, text=True,
            timeout=self.timeout, stdin=subprocess.DEVNULL,
        )
        if proc.returncode != 0:
            raise ChatError(proc.stderr.strip()[:300] or "claude failed")
        return proc.stdout.strip()

    def _context_or_raise(self, repo_override: str | None) -> tuple[Path, str]:
        repo = resolve_repo(self.cfg, repo_override)
        if repo is None:
            raise ChatError("no repo with vibe-learn session data found")
        return repo, _session_context(repo)

    def ask(self, question: str, repo_override: str | None = None) -> dict:
        repo, context = self._context_or_raise(repo_override)
        answer = self._claude(
            "You are a learning companion. Ground your answer strictly in the "
            "session log provided. Speak plainly for text-to-speech: under 120 "
            "words, no markdown, no file paths unless essential.",
            f"{context}\n\nQuestion about this session: {question}",
        )
        return {"repo": repo.name, "response": answer}

    def digest(self, repo_override: str | None = None) -> dict:
        repo, context = self._context_or_raise(repo_override)
        answer = self._claude(
            "You are a learning companion summarizing an AI coding session "
            "aloud. Plain spoken prose, no markdown, under 150 words.",
            f"{context}\n\nGive a digest: what was built or changed, the key "
            "decisions and why, and one concept worth studying afterward.",
        )
        return {"repo": repo.name, "response": answer}

    def quiz_next(self, repo_override: str | None = None) -> dict:
        repo, context = self._context_or_raise(repo_override)
        question = self._claude(
            "You generate one short spoken quiz question at a time testing "
            "whether the developer understood what their AI assistant just "
            "did and why. Return only the question, one or two sentences, "
            "no markdown.",
            f"{context}\n\nGenerate the next quiz question.",
        )
        state = _load_state()
        state["quiz_question"] = question
        state["quiz_repo"] = str(repo)
        _save_state(state)
        return {"repo": repo.name, "response": question}

    def quiz_answer(self, answer: str) -> dict:
        state = _load_state()
        question = state.get("quiz_question")
        if not question:
            raise ChatError("no quiz question pending — call /quiz/next first")
        repo = Path(state.get("quiz_repo", "."))
        context = _session_context(repo) if (repo / ".vibe-learn").exists() else ""
        verdict = self._claude(
            "You are grading a spoken quiz answer. Start with 'Correct' or "
            "'Not quite', then give a one- or two-sentence explanation. Plain "
            "spoken prose, no markdown.",
            f"{context}\n\nQuiz question: {question}\n"
            f"The developer answered (via speech-to-text): {answer}",
        )
        state.pop("quiz_question", None)
        _save_state(state)
        return {"repo": repo.name, "response": verdict}
