"""Local consent audit log for the cardputer-mcp daemon.

Why this exists: the `confirm` tool is the project's security keystone — an
irreversible operation cannot proceed without a physical, un-forgeable hold on
the device. But a live gesture leaves no trace: a week later you can't answer
"what did that agent get me to approve, and when?" This is the honest,
non-cryptographic first rung of the signed-consent-receipts roadmap item: an
append-only JSONL trail of every `confirm` decision — who asked (the
token-derived agent label), what (the title + the action-diff `details` you
actually approved), the outcome (confirmed / cancelled / timeout / …), and how
long you held. It records *decisions*, not just approvals, so a denial or a
timeout is on the record too.

Design mirrors ratelimit.py: tiny, dependency-free, with an injectable clock so
tests are deterministic. Writing is strictly best-effort — an audit-log failure
(bad path, full disk, permissions) must NEVER break a confirm round-trip, so
`record()` swallows OSError and reports it through an optional `warn` hook
instead of raising. One JSON object per line keeps the trail greppable and
append-only (no rewrite of prior entries), which is the point of an audit log.
"""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Callable, Optional


class ConsentAuditLog:
    """Append-only JSONL record of `confirm` decisions.

    Usage::

        audit = ConsentAuditLog(Path.home() / ".cardputer-mcp" / "audit.log")
        audit.record(
            tool="confirm", agent="managed-agent",
            title="DROP customers", details="DELETE FROM customers;",
            outcome="confirmed", hold_ms=3120,
        )

    A ``path`` of ``None`` disables the log entirely (every ``record`` is a
    no-op) — that's how the operator opts out via the environment. The clock is
    injectable purely for deterministic tests; in production it's wall-clock
    ``time.time`` so the ``ts`` field lines up with everything else on the host.
    """

    def __init__(
        self,
        path: Optional[Path],
        clock: Callable[[], float] = time.time,
        warn: Optional[Callable[[str], None]] = None,
    ) -> None:
        self._path = Path(path) if path is not None else None
        self._clock = clock
        self._warn = warn

    @property
    def enabled(self) -> bool:
        return self._path is not None

    @property
    def path(self) -> Optional[Path]:
        return self._path

    def record(
        self,
        *,
        tool: str,
        agent: str,
        title: str,
        outcome: str,
        details: Optional[str] = None,
        hold_ms: Optional[int] = None,
    ) -> None:
        """Append one decision to the log. Never raises.

        ``details`` and ``hold_ms`` are omitted from the record when ``None``
        so a confirm with no action-diff, or a non-``confirmed`` outcome, stays
        compact. Field order is insertion order (``ts`` first) so a human
        tailing the file reads it left-to-right in the order they'd expect.
        """
        if self._path is None:
            return

        entry = {
            "ts": round(float(self._clock()), 3),
            "tool": tool,
            "agent": agent,
            "title": title,
            "outcome": outcome,
        }
        if details is not None:
            entry["details"] = details
        if hold_ms is not None:
            entry["hold_ms"] = int(hold_ms)

        line = json.dumps(entry, ensure_ascii=False) + "\n"
        try:
            self._path.parent.mkdir(parents=True, exist_ok=True)
            with open(self._path, "a", encoding="utf-8") as f:
                f.write(line)
        except OSError as e:
            # Best-effort: a broken audit log must not take down a confirm.
            if self._warn is not None:
                self._warn(f"audit log write failed: {e}")
