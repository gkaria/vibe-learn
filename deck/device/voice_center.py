"""vibe-deck Voice Center — speak to Claude, ChatGPT, or Learn mode.

Adapted from cardputer-claude-os's push_to_claude.py. Instead of a cloud
Worker, audio POSTs over LAN HTTP to the vibe-deck gateway on the Mac,
which does local STT and routes to subscription-backed CLIs ($0/command).

Targets (1/2/3 or ,// to cycle, sticky):
  1 claude   — chat via `claude -p` on the Mac
  2 chatgpt  — chat via `codex exec` on the Mac
  3 learn    — vibe-learn-grounded answers, spoken aloud on the Mac
               (D = spoken digest, G = quiz round: question is spoken,
               answer it by voice with SPACE, verdict comes back spoken)

State machine (per target):
  IDLE       → SPACE      → RECORDING → UPLOADING → SHOWING | ERROR
  IDLE       → T          → TYPING    → UPLOADING → ...
  IDLE(learn)→ D / G      → UPLOADING → SHOWING (digest / quiz question)
  SHOWING(quiz pending) → SPACE → record answer → /quiz/answer
  any        → Q / ESC    → exit (machine.reset)
"""

import gc
import os
import time

import M5
import machine
from hardware import MatrixKeyboard


# ---- DEPLOYMENT-SPECIFIC CONSTANTS ----------------------------------
# Loaded from apps/config.py at runtime (gitignored — copy
# config.example.py to config.py and fill in your gateway URL + secret).
try:
    from . import config as _cfg  # type: ignore
except Exception:
    try:
        import config as _cfg  # type: ignore
    except Exception:
        _cfg = None

_GW_BASE = (getattr(_cfg, "GATEWAY_URL", "") if _cfg else "").rstrip("/")
GATEWAY_SECRET = getattr(_cfg, "GATEWAY_SECRET", "") if _cfg else ""
_DEFAULT_TARGET = getattr(_cfg, "DEFAULT_TARGET", "claude") if _cfg else "claude"

_TARGETS = ("claude", "chatgpt", "learn")
_TARGET_TITLES = {
    "claude": "Ask Claude",
    "chatgpt": "Ask ChatGPT",
    "learn": "Learn",
}
# ---------------------------------------------------------------------


# 16 kHz / 16-bit signed / mono. The Cardputer-Adv's PDM mic is
# hardware-locked to 16 kHz on this firmware (see push_to_claude.py
# history) — stay at 16 kHz and bound the cap instead.
_RATE = 16000
_BITS = 16
_CHANNELS = 1
_BYTES_PER_SAMPLE = _BITS // 8 * _CHANNELS

# recordWavFile is fixed-duration (no clean early stop).
_MAX_SECONDS = 6

_AUDIO_PATH = "/flash/last.wav"


# Theme — matches the rest of the bundle.
_BLACK = 0x000000
_ORANGE = 0xCC785C
_CREAM = 0xF0EEE6
_DARK = 0x1F1F1F
_GRAY_MID = 0x777777
_GREEN = 0x00FF00
_RED = 0xFF0000

_LCD = M5.Lcd
_W = 240
_H = 135


# ---- UI HELPERS -----------------------------------------------------

def _set_font():
    try:
        _LCD.setFont(_LCD.FONTS.DejaVu9)
    except Exception as e:
        print("deck: setFont fallback:", e)


def _draw_chrome(title, hint):
    _LCD.fillScreen(_BLACK)
    _LCD.fillRect(0, 0, _W, 20, _DARK)
    _LCD.fillRect(0, 20, _W, 1, _ORANGE)
    _LCD.setTextSize(1)
    _LCD.setTextColor(_ORANGE, _DARK)
    _LCD.drawString(title, 6, 5)

    _LCD.fillRect(0, _H - 18, _W, 18, _DARK)
    _LCD.setTextColor(_GRAY_MID, _DARK)
    _LCD.drawString(hint, (_W - _LCD.textWidth(hint)) // 2, _H - 14)


def _title_for(target):
    idx = _TARGETS.index(target) + 1
    return "deck {}/3 - {}".format(idx, _TARGET_TITLES[target])


def _hint_for(target):
    if target == "learn":
        return "SPACE ask  D digest  G quiz  Q back"
    return "SPACE voice  T text  N new  Q back"


def _draw_centered(text, y, color=_CREAM, size=1):
    _LCD.setTextSize(size)
    _LCD.setTextColor(color, _BLACK)
    _LCD.drawString(text, (_W - _LCD.textWidth(text)) // 2, y)


def _wrap_lines(text, max_w_px, char_size=1):
    """Greedy word-wrap for the 240 px content area."""
    _LCD.setTextSize(char_size)
    words = (text or "").split()
    lines = []
    cur = ""
    for w in words:
        cand = w if not cur else cur + " " + w
        if _LCD.textWidth(cand) <= max_w_px:
            cur = cand
        else:
            if cur:
                lines.append(cur)
            cur = w
            while _LCD.textWidth(cur) > max_w_px and len(cur) > 1:
                cut = len(cur) - 1
                while cut > 1 and _LCD.textWidth(cur[:cut]) > max_w_px:
                    cut -= 1
                lines.append(cur[:cut])
                cur = cur[cut:]
    if cur:
        lines.append(cur)
    return lines


def _draw_idle(target, wifi_ok, status_msg=None):
    _draw_chrome(_title_for(target), _hint_for(target))
    _draw_centered(_TARGET_TITLES[target], 34, _CREAM, 2)
    if target == "learn":
        _draw_centered("SPACE = ask about the session", 62, _GRAY_MID, 1)
        _draw_centered("D = digest   G = quiz me", 78, _GRAY_MID, 1)
    else:
        _draw_centered("SPACE = voice    T = text", 62, _GRAY_MID, 1)
        _draw_centered("N = new chat", 78, _GRAY_MID, 1)
    _draw_centered("1/2/3 or , / to switch target", 92, _GRAY_MID, 1)
    if status_msg:
        _draw_centered(status_msg, 106, _GREEN, 1)
    elif wifi_ok:
        _draw_centered("WiFi: online", 106, _GREEN, 1)
    else:
        _draw_centered("WiFi: OFFLINE", 106, _RED, 1)


def _draw_typing(target, buf, cursor_on):
    _draw_chrome("Type - " + _TARGET_TITLES[target], "Enter send  Esc back")
    _LCD.setTextSize(1)
    _LCD.setTextColor(_GRAY_MID, _BLACK)
    _LCD.drawString("> ", 6, 28)
    _LCD.setTextColor(_CREAM, _BLACK)

    lines = _wrap_lines(buf or " ", _W - 24, 1) or [""]
    if len(lines) > 5:
        lines = lines[-5:]
    y = 28
    for line in lines:
        _LCD.fillRect(18, y, _W - 24, 12, _BLACK)
        _LCD.drawString(line, 18, y)
        y += 12

    last_line = lines[-1] if lines else ""
    cur_x = 18 + _LCD.textWidth(last_line)
    cur_y = y - 12
    if cursor_on:
        _LCD.fillRect(cur_x, cur_y + 1, 6, 10, _ORANGE)
    else:
        _LCD.fillRect(cur_x, cur_y + 1, 6, 10, _BLACK)


# Pulsing dots — five orange circles that "breathe" left-to-right while
# recording.
_DOT_COUNT = 5
_DOT_RADIUS = 5
_DOT_SPACING = 22


def _draw_recording_initial(label="Recording"):
    _LCD.fillRect(0, 21, _W, _H - 21 - 18, _BLACK)
    _draw_centered(label, 36, _ORANGE, 2)
    _draw_centered("speak now ({}s)".format(_MAX_SECONDS), 96, _GRAY_MID, 1)
    _LCD.fillRect(0, 60, _W, 24, _BLACK)
    _LCD.fillRect(0, _H - 18, _W, 18, _DARK)
    _LCD.setTextColor(_GRAY_MID, _DARK)
    h = "Q/ESC abort"
    _LCD.drawString(h, (_W - _LCD.textWidth(h)) // 2, _H - 14)


def _draw_recording_dots(phase):
    total_w = (_DOT_COUNT - 1) * _DOT_SPACING + _DOT_RADIUS * 2
    x0 = (_W - total_w) // 2 + _DOT_RADIUS
    y = 72
    _LCD.fillRect(0, y - _DOT_RADIUS - 2, _W, _DOT_RADIUS * 2 + 4, _BLACK)
    for i in range(_DOT_COUNT):
        cx = x0 + i * _DOT_SPACING
        if i == phase:
            _LCD.fillCircle(cx, y, _DOT_RADIUS, _ORANGE)
        else:
            _LCD.fillCircle(cx, y, _DOT_RADIUS - 2, _DARK)


def _draw_uploading(stage="thinking", detail=""):
    _LCD.fillRect(0, 21, _W, _H - 21 - 18, _BLACK)
    _draw_centered(stage, 50, _ORANGE, 2)
    if detail:
        _draw_centered(detail, 80, _GRAY_MID, 1)
    else:
        _draw_centered("asking the gateway", 80, _GRAY_MID, 1)


def _result_layout(transcript, response):
    _LCD.setTextSize(1)
    t_lines = _wrap_lines("you: " + (transcript or "(silent)"), _W - 12, 1)[:2]
    response_y = 24 + len(t_lines) * 12 + 10
    max_visible = max(1, (_H - 18 - response_y) // 12)
    r_lines = _wrap_lines(response or "(empty)", _W - 12, 1)
    return t_lines, r_lines, response_y, max_visible


def _draw_result(target, transcript, response, scroll=0, quiz_pending=False):
    t_lines, r_lines, response_y, max_visible = _result_layout(
        transcript, response,
    )
    can_scroll = len(r_lines) > max_visible
    if quiz_pending:
        hint = "SPACE answer by voice  Q back"
    elif can_scroll:
        hint = "; . scroll  SPACE  Q"
    else:
        hint = "SPACE voice  T text  Q back"
    _draw_chrome(_title_for(target), hint)

    _LCD.setTextSize(1)
    _LCD.setTextColor(_GRAY_MID, _BLACK)
    y = 24
    for line in t_lines:
        _LCD.drawString(line, 6, y)
        y += 12
    _LCD.fillRect(6, y + 2, _W - 12, 1, _DARK)

    _LCD.setTextColor(_CREAM, _BLACK)
    visible = r_lines[scroll:scroll + max_visible]
    y = response_y
    for line in visible:
        _LCD.drawString(line, 6, y)
        y += 12

    if can_scroll:
        if scroll > 0:
            _LCD.fillTriangle(
                _W - 8, response_y + 2,
                _W - 2, response_y + 2,
                _W - 5, response_y - 3,
                _ORANGE,
            )
        if scroll + max_visible < len(r_lines):
            bottom_y = response_y + (len(visible) - 1) * 12
            _LCD.fillTriangle(
                _W - 8, bottom_y + 6,
                _W - 2, bottom_y + 6,
                _W - 5, bottom_y + 11,
                _ORANGE,
            )


def _draw_error(msg):
    _draw_chrome("deck - error", "SPACE retry  Q/ESC back")
    _LCD.setTextSize(1)
    _LCD.setTextColor(_RED, _BLACK)
    _LCD.drawString("Error", 6, 28)
    _LCD.setTextColor(_CREAM, _BLACK)
    for i, line in enumerate(_wrap_lines(msg, _W - 12, 1)[:6]):
        _LCD.drawString(line, 6, 46 + i * 12)


# ---- KEY HELPERS ----------------------------------------------------

def _as_char(k):
    if k is None:
        return None
    if isinstance(k, int):
        if 0x20 <= k <= 0x7E:
            return chr(k)
        return None
    if isinstance(k, str) and k:
        return k[0]
    return None


def _is_exit(k):
    if isinstance(k, int) and k == 0x1B:
        return True
    ch = _as_char(k)
    return ch is not None and ch.lower() == "q"


def _is_space(k):
    return (isinstance(k, int) and k == 0x20) or _as_char(k) == " "


def _is_char(k, target_char):
    ch = _as_char(k)
    return ch is not None and ch.lower() == target_char


def _is_enter(k):
    if isinstance(k, int) and k in (0x0A, 0x0D):
        return True
    return isinstance(k, str) and k in ("\r", "\n")


def _is_backspace(k):
    if isinstance(k, int) and k in (0x08, 0x7F):
        return True
    return isinstance(k, str) and k in ("\b", "\x7f")


def _scroll_intent(k):
    """; = up, . = down — same mapping as the launcher."""
    ch = _as_char(k)
    if ch == ";":
        return "up"
    if ch == ".":
        return "down"
    return None


def _target_intent(k, current):
    """1/2/3 select a target directly; , and / cycle."""
    ch = _as_char(k)
    if ch in ("1", "2", "3"):
        return _TARGETS[int(ch) - 1]
    idx = _TARGETS.index(current)
    if ch == ",":
        return _TARGETS[(idx - 1) % len(_TARGETS)]
    if ch == "/":
        return _TARGETS[(idx + 1) % len(_TARGETS)]
    return None


def _printable_char(k):
    ch = _as_char(k)
    if ch is not None and 0x20 <= ord(ch) <= 0x7E:
        return ch
    return None


# ---- NETWORK --------------------------------------------------------

def _free_internal_ram():
    """Tear down NimBLE and force-collect. Less critical for plain-HTTP
    LAN posts than it was for TLS-to-Cloudflare, but the launcher leaves
    BLE active and ~30 KB of reclaimed internal RAM is still welcome."""
    try:
        import bluetooth
        ble = bluetooth.BLE()
        if ble.active():
            ble.active(False)
    except Exception as e:
        print("deck: ble teardown warn:", e)
    gc.collect()
    gc.collect()


def _ensure_wifi():
    try:
        import network
        sta = network.WLAN(network.STA_IF)
        if not sta.active():
            sta.active(True)
        if sta.isconnected():
            return True
        try:
            import wifi_event
            res = wifi_event.connect()
            return bool(res.get("ok"))
        except Exception as e:
            print("deck: wifi_event err:", e)
            return False
    except Exception as e:
        print("deck: ensure_wifi err:", e)
        return False


def _record_to_file(kb):
    """Capture audio to _AUDIO_PATH via M5.Mic.recordWavFile (the only
    reliable capture path on this UIFlow build — see push_to_claude.py
    for the full investigation). Fixed duration, animated dots, Q/ESC
    aborts. Returns sample-count estimate (0 on error)."""
    try:
        os.remove(_AUDIO_PATH)
    except OSError:
        pass

    M5.Mic.begin()
    try:
        try:
            M5.Mic.setSampleRate(_RATE)
        except Exception as e:
            print("deck: setSampleRate warn:", e)

        try:
            M5.Mic.recordWavFile(_AUDIO_PATH, _RATE, _MAX_SECONDS)
        except TypeError:
            try:
                M5.Mic.recordWavFile(_AUDIO_PATH, _MAX_SECONDS, _RATE)
            except Exception as e:
                print("deck: recordWavFile err:", e)
                return 0

        deadline = time.ticks_add(
            time.ticks_ms(), (_MAX_SECONDS + 2) * 1000,
        )
        last_phase = -1
        last_ms = 0
        while M5.Mic.isRecording():
            now = time.ticks_ms()
            if time.ticks_diff(now, deadline) > 0:
                try:
                    M5.Mic.end()
                except Exception:
                    pass
                break
            if time.ticks_diff(now, last_ms) >= 120:
                phase = (now // 360) % _DOT_COUNT
                if phase != last_phase:
                    _draw_recording_dots(phase)
                    last_phase = phase
                last_ms = now
            kb.tick()
            k = kb.get_key()
            if k is not None and _is_exit(k):
                try:
                    M5.Mic.end()
                except Exception:
                    pass
                raise KeyboardInterrupt()
            time.sleep_ms(40)
    finally:
        try:
            M5.Mic.end()
        except Exception as e:
            print("deck: mic.end warn:", e)

    try:
        size = os.stat(_AUDIO_PATH)[6]
    except OSError:
        return 0
    return max(0, (size - 44) // _BYTES_PER_SAMPLE)


def _split_url(url):
    """→ (use_tls, host, port, path). Supports http:// and https://."""
    if url.startswith("https://"):
        use_tls, rest, default_port = True, url[8:], 443
    elif url.startswith("http://"):
        use_tls, rest, default_port = False, url[7:], 80
    else:
        raise RuntimeError("bad url: " + url)
    slash = rest.find("/")
    if slash == -1:
        host_port, path = rest, "/"
    else:
        host_port, path = rest[:slash], rest[slash:]
    if ":" in host_port:
        host, port_str = host_port.split(":", 1)
        port = int(port_str)
    else:
        host, port = host_port, default_port
    return use_tls, host, port, path


def _post_file_stream(url, file_path, headers, chunk_size=2048, timeout_s=90):
    """File-streamed POST over plain HTTP or HTTPS.

    The gateway lives on the LAN over plain HTTP, which sidesteps the
    mbedTLS internal-RAM pressure entirely; the TLS branch is kept for
    anyone pointing this at a tunnel URL. Returns (status, body_bytes).
    """
    import socket

    use_tls, host, port, http_path = _split_url(url)
    file_size = os.stat(file_path)[6]

    gc.collect()
    gc.collect()

    addr = socket.getaddrinfo(host, port)[0][-1]
    s = socket.socket()
    try:
        s.settimeout(timeout_s)
    except Exception:
        pass
    s.connect(addr)
    if use_tls:
        import ssl as _ssl
        ss = _ssl.wrap_socket(s, server_hostname=host)
    else:
        ss = s

    try:
        head = (
            "POST {} HTTP/1.1\r\n"
            "Host: {}\r\n"
            "User-Agent: vibe-deck\r\n"
            "Content-Length: {}\r\n"
            "Connection: close\r\n"
        ).format(http_path, host, file_size)
        for k, v in headers.items():
            head += "{}: {}\r\n".format(k, v)
        head += "\r\n"
        ss.write(head.encode())

        buf = bytearray(chunk_size)
        with open(file_path, "rb") as f:
            while True:
                got = f.readinto(buf)
                if not got:
                    break
                if got < chunk_size:
                    ss.write(memoryview(buf)[:got])
                else:
                    ss.write(buf)

        resp = bytearray()
        rb = bytearray(512)
        while len(resp) < 8192:
            try:
                g = ss.readinto(rb)
            except OSError:
                break
            if not g:
                break
            resp += rb[:g]
        raw = bytes(resp)
    finally:
        try:
            ss.close()
        except Exception:
            pass
        if use_tls:
            try:
                s.close()
            except Exception:
                pass

    sep = raw.find(b"\r\n\r\n")
    if sep == -1:
        raise RuntimeError("malformed http response")
    head_text = raw[:sep].decode("utf-8", "replace")
    body_bytes = raw[sep + 4:]
    first_line = head_text.split("\r\n", 1)[0]
    parts = first_line.split(" ", 2)
    if len(parts) < 2:
        raise RuntimeError("bad status line: " + first_line)
    return int(parts[1]), body_bytes


def _headers(json_body=False):
    h = {"x-gateway-secret": GATEWAY_SECRET}
    if json_body:
        h["content-type"] = "application/json"
    return h


def _post_json(path, payload=None, timeout=150):
    """Small JSON POST via requests (text prompts, reset, digest, quiz)."""
    _free_internal_ram()
    import json as _json
    import requests
    body = _json.dumps(payload or {}).encode()
    r = requests.post(
        _GW_BASE + path, data=body, headers=_headers(json_body=True),
        timeout=timeout,
    )
    try:
        if r.status_code != 200:
            raise RuntimeError(
                "gateway {}: {}".format(r.status_code, r.text[:120]),
            )
        return r.json()
    finally:
        try:
            r.close()
        except Exception:
            pass


def _post_recording(path):
    """POST the captured WAV to the given gateway path. Returns parsed
    JSON; raises on failure (including an empty file)."""
    try:
        size = os.stat(_AUDIO_PATH)[6]
    except OSError as e:
        raise RuntimeError("no audio file: {}".format(e))
    if size <= 44:
        raise RuntimeError("empty recording")

    _free_internal_ram()
    _draw_uploading("thinking", "{} KB sent to gateway".format(size // 1024))

    headers = _headers()
    headers["content-type"] = "audio/wav"
    status, resp_body = _post_file_stream(
        _GW_BASE + path, _AUDIO_PATH, headers, chunk_size=2048, timeout_s=150,
    )
    gc.collect()

    if status != 200:
        snippet = resp_body[:160].decode("utf-8", "replace")
        raise RuntimeError("gateway {}: {}".format(status, snippet))
    import json as _json
    return _json.loads(resp_body)


# ---- MAIN -----------------------------------------------------------

def run():
    _set_font()
    if not _GW_BASE or not GATEWAY_SECRET:
        _draw_error(
            "Not configured.\n"
            "Copy apps/config.example.py\nto apps/config.py\n"
            "and set GATEWAY_URL\n+ GATEWAY_SECRET."
        )
        kb = MatrixKeyboard()
        while True:
            kb.tick()
            if _is_exit(kb.get_key()):
                return
            time.sleep_ms(50)

    target = _DEFAULT_TARGET if _DEFAULT_TARGET in _TARGETS else "claude"
    wifi_ok = _ensure_wifi()
    _draw_idle(target, wifi_ok)
    kb = MatrixKeyboard()
    time.sleep_ms(400)

    state = "idle"
    text_buf = ""
    cursor_on = True
    last_blink_ms = 0
    last_transcript = ""
    last_response = ""
    scroll = 0
    quiz_pending = False  # a quiz question is on screen awaiting a voice answer

    def _record_and_post(path):
        """Shared voice round-trip: record → POST → (transcript, response).
        Raises KeyboardInterrupt if the user aborted the recording."""
        gc.collect()
        _draw_recording_initial()
        _draw_recording_dots(0)
        _record_to_file(kb)
        _draw_uploading()
        return _post_recording(path)

    def _show(result, pending=False):
        nonlocal last_transcript, last_response, scroll, quiz_pending, state
        last_transcript = result.get("transcript", "")
        last_response = result.get("response", "")
        scroll = 0
        quiz_pending = pending
        state = "showing"
        _draw_result(target, last_transcript, last_response, scroll, pending)

    def _fail(e):
        nonlocal state, quiz_pending
        msg = str(e)[:200]
        print("deck: err:", msg)
        state = "error"
        quiz_pending = False
        _draw_error(msg)

    try:
        while True:
            kb.tick()
            k = kb.get_key()

            if state != "typing" and _is_exit(k):
                return

            new_target = None
            if state in ("idle", "showing") and not quiz_pending:
                new_target = _target_intent(k, target)
            if new_target and new_target != target:
                target = new_target
                state = "idle"
                _draw_idle(target, wifi_ok)
                time.sleep_ms(150)
                continue

            if state == "idle":
                if _is_space(k):
                    try:
                        if target == "learn":
                            result = _record_and_post("/voice?target=learn")
                        else:
                            result = _record_and_post("/voice?target=" + target)
                        _show(result)
                    except KeyboardInterrupt:
                        return
                    except Exception as e:
                        _fail(e)
                    try:
                        os.remove(_AUDIO_PATH)
                    except OSError:
                        pass
                    gc.collect()

                elif target != "learn" and _is_char(k, "t"):
                    state = "typing"
                    text_buf = ""
                    cursor_on = True
                    last_blink_ms = time.ticks_ms()
                    _draw_typing(target, text_buf, cursor_on)

                elif target != "learn" and _is_char(k, "n"):
                    try:
                        _post_json("/reset", {"target": target}, timeout=15)
                        msg = "memory cleared"
                    except Exception:
                        msg = "reset failed"
                    _draw_idle(target, wifi_ok, status_msg=msg)
                    time.sleep_ms(900)
                    _draw_idle(target, wifi_ok)

                elif target == "learn" and _is_char(k, "d"):
                    _draw_uploading("digest", "summarizing the session")
                    try:
                        result = _post_json("/learn/digest")
                        result["transcript"] = "digest of " + result.get("repo", "?")
                        _show(result)
                    except Exception as e:
                        _fail(e)

                elif target == "learn" and _is_char(k, "g"):
                    _draw_uploading("quiz", "writing a question")
                    try:
                        result = _post_json("/quiz/next")
                        result["transcript"] = "quiz - answer with SPACE"
                        _show(result, pending=True)
                    except Exception as e:
                        _fail(e)

            elif state == "typing":
                if k is not None and isinstance(k, int) and k == 0x1B:
                    state = "idle"
                    text_buf = ""
                    wifi_ok = _ensure_wifi()
                    _draw_idle(target, wifi_ok)
                elif _is_enter(k):
                    if text_buf.strip():
                        _draw_uploading()
                        try:
                            result = _post_json(
                                "/text",
                                {"prompt": text_buf.strip(), "target": target},
                            )
                            _show(result)
                        except Exception as e:
                            _fail(e)
                        text_buf = ""
                        gc.collect()
                elif _is_backspace(k):
                    if text_buf:
                        text_buf = text_buf[:-1]
                        _draw_typing(target, text_buf, cursor_on)
                else:
                    ch = _printable_char(k)
                    if ch is not None and len(text_buf) < 240:
                        text_buf += ch
                        _draw_typing(target, text_buf, cursor_on)

                if state == "typing":
                    now = time.ticks_ms()
                    if time.ticks_diff(now, last_blink_ms) >= 500:
                        cursor_on = not cursor_on
                        last_blink_ms = now
                        _draw_typing(target, text_buf, cursor_on)

            elif state == "showing":
                intent = _scroll_intent(k)
                if intent is not None:
                    _, r_lines, _, max_visible = _result_layout(
                        last_transcript, last_response,
                    )
                    max_scroll = max(0, len(r_lines) - max_visible)
                    if intent == "up":
                        new_scroll = max(0, scroll - 1)
                    else:
                        new_scroll = min(max_scroll, scroll + 1)
                    if new_scroll != scroll:
                        scroll = new_scroll
                        _draw_result(
                            target, last_transcript, last_response,
                            scroll, quiz_pending,
                        )
                elif _is_space(k):
                    if quiz_pending:
                        # Voice-answer the pending quiz question.
                        try:
                            result = _record_and_post("/quiz/answer")
                            _show(result)
                        except KeyboardInterrupt:
                            return
                        except Exception as e:
                            _fail(e)
                        try:
                            os.remove(_AUDIO_PATH)
                        except OSError:
                            pass
                        gc.collect()
                    else:
                        state = "idle"
                        wifi_ok = _ensure_wifi()
                        _draw_idle(target, wifi_ok)
                elif target != "learn" and _is_char(k, "t"):
                    state = "typing"
                    text_buf = ""
                    cursor_on = True
                    last_blink_ms = time.ticks_ms()
                    _draw_typing(target, text_buf, cursor_on)
                elif target != "learn" and _is_char(k, "n"):
                    try:
                        _post_json("/reset", {"target": target}, timeout=15)
                        msg = "memory cleared"
                    except Exception:
                        msg = "reset failed"
                    state = "idle"
                    wifi_ok = _ensure_wifi()
                    _draw_idle(target, wifi_ok, status_msg=msg)
                    time.sleep_ms(900)
                    _draw_idle(target, wifi_ok)
                elif target == "learn" and _is_char(k, "g") and not quiz_pending:
                    _draw_uploading("quiz", "writing a question")
                    try:
                        result = _post_json("/quiz/next")
                        result["transcript"] = "quiz - answer with SPACE"
                        _show(result, pending=True)
                    except Exception as e:
                        _fail(e)

            elif state == "error":
                if _is_space(k):
                    state = "idle"
                    wifi_ok = _ensure_wifi()
                    _draw_idle(target, wifi_ok)
                elif target != "learn" and _is_char(k, "t"):
                    state = "typing"
                    text_buf = ""
                    cursor_on = True
                    last_blink_ms = time.ticks_ms()
                    _draw_typing(target, text_buf, cursor_on)

            time.sleep_ms(40)
    finally:
        try:
            M5.Mic.end()
        except Exception:
            pass
        try:
            _LCD.fillScreen(_BLACK)
        except Exception:
            pass
        time.sleep_ms(200)
        machine.reset()


run()
