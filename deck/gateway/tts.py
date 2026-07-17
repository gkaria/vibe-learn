"""Spoken output via macOS `say` — free, local, and routed to whatever
audio output the Mac currently uses (built-in, Bluetooth speaker, AirPods).

Utterances are serialized on a background thread so overlapping requests
don't talk over each other. Upgrade path to neural TTS (e.g. Kokoro via
mlx-audio) is a drop-in replacement for _speak_now.
"""

from __future__ import annotations

import queue
import subprocess
import threading


class Speaker:
    def __init__(self, cfg):
        self.enabled = cfg.get("TTS_ENABLED") == "1"
        self.voice = cfg.get("TTS_VOICE")
        self.rate = cfg.get("TTS_RATE")
        self._q: queue.Queue[str] = queue.Queue()
        if self.enabled:
            threading.Thread(target=self._worker, daemon=True).start()

    def speak(self, text: str) -> bool:
        """Queue text for speech. Returns whether it will be spoken."""
        if not self.enabled or not text.strip():
            return False
        self._q.put(text.strip())
        return True

    def _worker(self):
        while True:
            text = self._q.get()
            self._speak_now(text)

    def _speak_now(self, text: str):
        cmd = ["say", "-r", self.rate]
        if self.voice:
            cmd += ["-v", self.voice]
        subprocess.run(cmd, input=text, text=True, check=False)
