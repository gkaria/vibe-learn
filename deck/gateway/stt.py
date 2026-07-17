"""Local speech-to-text for the vibe-deck gateway.

Default backend is NVIDIA Parakeet via parakeet-mlx (Apple Silicon,
~sub-second for short clips, $0). mlx-whisper is the fallback backend.
The model is loaded once at startup and reused for every request.
"""

from __future__ import annotations

import time


class Transcriber:
    def __init__(self, backend: str, model_name: str):
        self.backend = backend
        self.model_name = model_name
        self._model = None

    def warm(self):
        """Load the model up front so the first request isn't slow."""
        if self._model is not None:
            return
        t0 = time.time()
        if self.backend == "parakeet":
            from parakeet_mlx import from_pretrained

            self._model = from_pretrained(self.model_name)
        elif self.backend == "mlx_whisper":
            import mlx_whisper  # noqa: F401 — model loads lazily per call

            self._model = mlx_whisper
        else:
            raise ValueError(f"unknown STT_BACKEND: {self.backend}")
        print(f"[stt] {self.backend} ready in {time.time() - t0:.1f}s")

    def transcribe(self, wav_path: str) -> str:
        self.warm()
        t0 = time.time()
        if self.backend == "parakeet":
            text = self._parakeet_transcribe(wav_path)
        else:
            text = self._model.transcribe(wav_path)["text"].strip()
        print(f"[stt] {time.time() - t0:.2f}s: {text[:80]!r}")
        return text

    def _parakeet_transcribe(self, wav_path: str) -> str:
        """Decode the WAV ourselves (soundfile + soxr resample) instead of
        going through parakeet_mlx.load_audio, which shells out to ffmpeg —
        a system dependency we'd otherwise force on every install. The
        device always sends 16 kHz mono PCM, matching the model's rate."""
        import mlx.core as mx
        import soundfile as sf
        from parakeet_mlx.audio import get_logmel

        audio, rate = sf.read(wav_path, dtype="float32")
        if audio.ndim > 1:
            audio = audio.mean(axis=1)
        target_rate = self._model.preprocessor_config.sample_rate
        if rate != target_rate:
            import soxr

            audio = soxr.resample(audio, rate, target_rate)
        # float32, matching parakeet_mlx.load_audio's output — get_logmel's
        # complex-STFT view arithmetic depends on the 4-byte dtype
        mel = get_logmel(mx.array(audio), self._model.preprocessor_config)
        result = self._model.generate(mel)[0]
        return result.text.strip()
