"""vibe-deck gateway — the Mac-side brain.

The Cardputer POSTs audio/text here over LAN HTTP; everything else
(local STT, subscription-backed CLI chat, vibe-learn grounding, TTS)
happens on this machine. Run with:

    cd deck && ~/.vibe-deck/venv/bin/uvicorn gateway.server:app \
        --host 0.0.0.0 --port 8756
"""

from __future__ import annotations

import tempfile
from pathlib import Path

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.concurrency import run_in_threadpool

from . import config
from .chat import ChatError, targets as chat_targets
from .learn import Learn
from .stt import Transcriber
from .tts import Speaker

cfg = config.load()
SECRET = cfg.secret  # fail closed at import if unset

stt = Transcriber(cfg.get("STT_BACKEND"), cfg.get("STT_MODEL"))
speaker = Speaker(cfg)
chats = chat_targets(cfg)
learn = Learn(cfg)

app = FastAPI(title="vibe-deck gateway")

CHAT_TARGETS = ("claude", "chatgpt")
ALL_TARGETS = CHAT_TARGETS + ("learn",)


@app.on_event("startup")
async def _warm():
    await run_in_threadpool(stt.warm)


@app.middleware("http")
async def _auth(request: Request, call_next):
    if request.headers.get("x-gateway-secret") != SECRET:
        from fastapi.responses import JSONResponse

        return JSONResponse({"error": "unauthorized"}, status_code=401)
    return await call_next(request)


async def _body_to_wav(request: Request) -> str:
    body = await request.body()
    if len(body) < 200:
        raise HTTPException(400, "audio body too small")
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        f.write(body)
        return f.name


async def _transcribe(request: Request) -> str:
    wav = await _body_to_wav(request)
    try:
        text = await run_in_threadpool(stt.transcribe, wav)
    finally:
        Path(wav).unlink(missing_ok=True)
    if not text:
        raise HTTPException(422, "could not transcribe audio")
    return text


async def _route(target: str, prompt: str, repo: str | None) -> dict:
    try:
        if target in CHAT_TARGETS:
            reply = await run_in_threadpool(chats[target].ask, prompt)
            return {"response": reply, "spoken": False}
        if target == "learn":
            result = await run_in_threadpool(learn.ask, prompt, repo)
            result["spoken"] = speaker.speak(result["response"])
            return result
    except ChatError as e:
        raise HTTPException(502, str(e))
    raise HTTPException(400, f"unknown target: {target}")


@app.get("/health")
async def health():
    return {
        "ok": True,
        "stt_backend": stt.backend,
        "tts_enabled": speaker.enabled,
        "targets": list(ALL_TARGETS),
    }


@app.post("/voice")
async def voice(
    request: Request,
    target: str = Query("claude"),
    repo: str | None = Query(None),
):
    transcript = await _transcribe(request)
    result = await _route(target, transcript, repo)
    return {"transcript": transcript, **result}


@app.post("/text")
async def text(request: Request):
    data = await request.json()
    prompt = (data.get("prompt") or "").strip()
    if not prompt:
        raise HTTPException(400, "prompt required")
    result = await _route(data.get("target", "claude"), prompt, data.get("repo"))
    return {"transcript": prompt, **result}


@app.post("/learn/digest")
async def learn_digest(request: Request):
    repo = (await request.json() if int(request.headers.get("content-length") or 0) else {}).get("repo")
    try:
        result = await run_in_threadpool(learn.digest, repo)
    except ChatError as e:
        raise HTTPException(502, str(e))
    result["spoken"] = speaker.speak(result["response"])
    return result


@app.post("/quiz/next")
async def quiz_next(request: Request):
    repo = (await request.json() if int(request.headers.get("content-length") or 0) else {}).get("repo")
    try:
        result = await run_in_threadpool(learn.quiz_next, repo)
    except ChatError as e:
        raise HTTPException(502, str(e))
    result["spoken"] = speaker.speak(result["response"])
    return result


@app.post("/quiz/answer")
async def quiz_answer(request: Request):
    if "json" in (request.headers.get("content-type") or ""):
        answer = ((await request.json()).get("answer") or "").strip()
        if not answer:
            raise HTTPException(400, "answer required")
    else:
        answer = await _transcribe(request)
    try:
        result = await run_in_threadpool(learn.quiz_answer, answer)
    except ChatError as e:
        raise HTTPException(502, str(e))
    result["spoken"] = speaker.speak(result["response"])
    return {"transcript": answer, **result}


@app.post("/reset")
async def reset(request: Request):
    data = {}
    if int(request.headers.get("content-length") or 0):
        data = await request.json()
    which = data.get("target")
    cleared = []
    for name, chat in chats.items():
        if which in (None, "all", name):
            chat.reset()
            cleared.append(name)
    return {"reset": cleared}
