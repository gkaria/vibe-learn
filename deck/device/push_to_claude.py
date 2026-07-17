"""Push-to-Claude — speak to ask Claude, get a reply on the LCD.

Tap SPACE to start, tap SPACE again to stop. Audio streams straight
to ``/flash/last.wav`` as it's captured so RAM use stays flat
regardless of clip length, then we POST the WAV body to a Cloudflare
Worker that runs Whisper for STT and Claude Haiku 4.5 for the reply.

State machine:
  IDLE       → SPACE      → RECORDING
  RECORDING  → SPACE      → UPLOADING  (also auto-stops at MAX_SECONDS)
  UPLOADING  → reply      → SHOWING
  UPLOADING  → error      → ERROR
  SHOWING    → SPACE      → IDLE
  ERROR      → SPACE      → IDLE
  any        → Q / ESC    → exit (machine.reset)

There's no visible timer; recording feels open-ended. The MAX_SECONDS
cap below is purely a safety bound on disk + upload size, not part
of the UX.
"""

import gc
import os
import struct
import time

import M5
import machine
from hardware import MatrixKeyboard


# ---- DEPLOYMENT-SPECIFIC CONSTANTS ----------------------------------
# Loaded from buddy/device/apps/config.py at runtime. That file is
# gitignored — copy ``config.example.py`` to ``config.py`` and fill in
# your own Cloudflare Worker URL + device secret. See ``worker/README.md``
# for how to deploy your own relay.
try:
    from . import config as _cfg  # type: ignore
except Exception:
    try:
        import config as _cfg  # type: ignore
    except Exception:
        _cfg = None

_WORKER_BASE = (getattr(_cfg, "WORKER_BASE", "") if _cfg else "").rstrip("/")
DEVICE_SECRET = getattr(_cfg, "DEVICE_SECRET", "") if _cfg else ""
WORKER_URL = _WORKER_BASE + "/ask"             # voice (raw WAV body)
WORKER_TEXT_URL = _WORKER_BASE + "/ask-text"   # text (JSON {prompt})
WORKER_RESET_URL = _WORKER_BASE + "/reset"     # clear server-side history
# ---------------------------------------------------------------------


# 16 kHz / 16-bit signed / mono. The Cardputer-Adv's PDM mic appears
# to be hardware-locked to 16 kHz on this firmware — calling
# setSampleRate(8000) was accepted silently but the recorded data
# stayed at 16 kHz, producing WAV files that Whisper interpreted as
# slowed-down audio (or hung on entirely). Stay at 16 kHz and bound
# the cap instead.
_RATE = 16000
_BITS = 16
_CHANNELS = 1
_BYTES_PER_SAMPLE = _BITS // 8 * _CHANNELS

# Recording duration. With M5.Mic.recordWavFile the firmware does the
# capture into a file directly — fixed duration (no tap-to-stop), but
# actual audio data we can transcribe (vs. the silent -8 samples my
# hand-rolled record() loop was producing).
_MAX_SECONDS = 6

# Chunk granularity for the mic capture loop. 50 ms = 400 samples at
# 8 kHz; small enough to keep keyboard-stop responsive, large enough
# to avoid chunk-setup overhead.
_CHUNK_SAMPLES = _RATE // 20
_CHUNK_BYTES = _CHUNK_SAMPLES * _BYTES_PER_SAMPLE

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
        print("p2c: setFont fallback:", e)


def _draw_chrome(title="Push to Claude", hint="SPACE record  Q/ESC back"):
    _LCD.fillScreen(_BLACK)
    _LCD.fillRect(0, 0, _W, 20, _DARK)
    _LCD.fillRect(0, 20, _W, 1, _ORANGE)
    _LCD.setTextSize(1)
    _LCD.setTextColor(_ORANGE, _DARK)
    _LCD.drawString(title, 6, 5)

    _LCD.fillRect(0, _H - 18, _W, 18, _DARK)
    _LCD.setTextColor(_GRAY_MID, _DARK)
    _LCD.drawString(hint, (_W - _LCD.textWidth(hint)) // 2, _H - 14)


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


def _draw_idle(wifi_ok, status_msg=None):
    _draw_chrome(hint="SPACE  T  N new  Q back")
    _draw_centered("Ask Claude", 36, _CREAM, 2)
    _draw_centered("SPACE = voice    T = text", 66, _GRAY_MID, 1)
    _draw_centered("N = new chat (clear memory)", 82, _GRAY_MID, 1)
    if status_msg:
        _draw_centered(status_msg, 100, _GREEN, 1)
    elif wifi_ok:
        _draw_centered("WiFi: online", 100, _GREEN, 1)
    else:
        _draw_centered("WiFi: OFFLINE", 100, _RED, 1)


def _draw_typing(buf, cursor_on):
    """Render the text-input screen with the buffer wrapped, plus a
    blinking cursor at the end of the last line. Called every ~250 ms
    to drive the blink and on every key press to reflect the buffer."""
    _draw_chrome(title="Type to Claude", hint="Enter send  Esc back")
    _LCD.setTextSize(1)
    _LCD.setTextColor(_GRAY_MID, _BLACK)
    _LCD.drawString("> ", 6, 28)
    _LCD.setTextColor(_CREAM, _BLACK)

    lines = _wrap_lines(buf or " ", _W - 24, 1) or [""]
    # Limit to 5 visible lines; truncate from the start if longer so
    # the user always sees what they're currently typing.
    if len(lines) > 5:
        lines = lines[-5:]
    y = 28
    for line in lines:
        _LCD.fillRect(18, y, _W - 24, 12, _BLACK)
        _LCD.drawString(line, 18, y)
        y += 12

    # Blinking caret at the end of the last drawn line.
    last_line = lines[-1] if lines else ""
    cur_x = 18 + _LCD.textWidth(last_line)
    cur_y = y - 12
    if cursor_on:
        _LCD.fillRect(cur_x, cur_y + 1, 6, 10, _ORANGE)
    else:
        _LCD.fillRect(cur_x, cur_y + 1, 6, 10, _BLACK)


# Pulsing dots — five orange circles that "breathe" left-to-right while
# recording. Replaces the literal countdown the user didn't want.
_DOT_COUNT = 5
_DOT_RADIUS = 5
_DOT_SPACING = 22


def _draw_recording_initial():
    _LCD.fillRect(0, 21, _W, _H - 21 - 18, _BLACK)
    _draw_centered("Recording", 36, _ORANGE, 2)
    _draw_centered("speak now ({}s)".format(_MAX_SECONDS), 96, _GRAY_MID, 1)
    _LCD.fillRect(0, 60, _W, 24, _BLACK)
    _LCD.fillRect(0, _H - 18, _W, 18, _DARK)
    _LCD.setTextColor(_GRAY_MID, _DARK)
    h = "Q/ESC abort"
    _LCD.drawString(h, (_W - _LCD.textWidth(h)) // 2, _H - 14)


def _draw_recording_dots(phase):
    """Animate a single bright dot moving across DOT_COUNT positions.
    Cheap, eye-catching, and gives an at-a-glance heartbeat without
    a numeric timer."""
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
        _draw_centered("uploading + asking Claude", 80, _GRAY_MID, 1)


def _result_layout(transcript, response):
    """Pre-wrap both halves of a result so scrolling can pick a window
    without re-wrapping every redraw. Returns (transcript_lines,
    response_lines, response_y, max_visible)."""
    _LCD.setTextSize(1)
    t_lines = _wrap_lines("you: " + (transcript or "(silent)"), _W - 12, 1)[:2]
    response_y = 24 + len(t_lines) * 12 + 10  # +10 covers the hairline gap
    max_visible = max(1, (_H - 18 - response_y) // 12)
    r_lines = _wrap_lines(response or "(empty)", _W - 12, 1)
    return t_lines, r_lines, response_y, max_visible


def _draw_result(transcript, response, scroll=0):
    """Render a result with optional scroll offset into the response.
    ``scroll`` is the index of the first response line to show; the
    caller bounds it to ``[0, len(r_lines) - max_visible]``."""
    t_lines, r_lines, response_y, max_visible = _result_layout(
        transcript, response,
    )
    can_scroll = len(r_lines) > max_visible
    hint = "SPACE voice  T text  Q back"
    if can_scroll:
        hint = "; . scroll  SPACE  T  Q"
    _draw_chrome(hint=hint)

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

    # Scroll indicators on the right edge — small orange triangles
    # only when there's something above/below the viewport.
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
    _draw_chrome(hint="SPACE retry  Q/ESC back")
    _LCD.setTextSize(1)
    _LCD.setTextColor(_RED, _BLACK)
    _LCD.drawString("Error", 6, 28)
    _LCD.setTextColor(_CREAM, _BLACK)
    for i, line in enumerate(_wrap_lines(msg, _W - 12, 1)[:6]):
        _LCD.drawString(line, 6, 46 + i * 12)


# ---- KEY HELPERS ----------------------------------------------------

def _is_exit(k):
    if k is None:
        return False
    if isinstance(k, int):
        if k == 0x1B:
            return True
        if 0x20 <= k <= 0x7E:
            k = chr(k)
        else:
            return False
    return isinstance(k, str) and k and k.lower() == "q"


def _is_space(k):
    if k is None:
        return False
    if isinstance(k, int):
        if k == 0x20:
            return True
        if 0x20 <= k <= 0x7E:
            k = chr(k)
        else:
            return False
    return isinstance(k, str) and k == " "


def _is_new_chat(k):
    """`n` or `N` → clear conversation history and start fresh."""
    if k is None:
        return False
    if isinstance(k, int):
        if 0x20 <= k <= 0x7E:
            k = chr(k)
        else:
            return False
    return isinstance(k, str) and k.lower() == "n"


def _is_text_trigger(k):
    """`t` or `T` while idle → enter text-input mode."""
    if k is None:
        return False
    if isinstance(k, int):
        if 0x20 <= k <= 0x7E:
            k = chr(k)
        else:
            return False
    return isinstance(k, str) and k.lower() == "t"


def _is_enter(k):
    if k is None:
        return False
    if isinstance(k, int) and k in (0x0A, 0x0D):
        return True
    return isinstance(k, str) and k in ("\r", "\n")


def _is_backspace(k):
    if k is None:
        return False
    # 0x08 (BS) or 0x7F (DEL); UIFlow's MatrixKeyboard has been
    # observed to use both depending on firmware vintage.
    if isinstance(k, int) and k in (0x08, 0x7F):
        return True
    return isinstance(k, str) and k in ("\b", "\x7f")


def _scroll_intent(k):
    """Return 'up' / 'down' for the Cardputer-Adv arrow cluster.
    Same key mapping the launcher uses (; / , = up; . / / = down)
    so users have one mental model for "scroll" across the bundle."""
    if k is None:
        return None
    if isinstance(k, int):
        if 0x20 <= k <= 0x7E:
            k = chr(k)
        else:
            return None
    if not isinstance(k, str) or not k:
        return None
    ch = k.lower()
    if ch in (";", ","):
        return "up"
    if ch in (".", "/"):
        return "down"
    return None


def _printable_char(k):
    """Return a single printable ASCII char to append to the input
    buffer, or None if the key isn't a regular character."""
    if k is None:
        return None
    if isinstance(k, int):
        if 0x20 <= k <= 0x7E:
            return chr(k)
        return None
    if isinstance(k, str) and k and 0x20 <= ord(k[0]) <= 0x7E:
        return k[0]
    return None


# ---- AUDIO ----------------------------------------------------------

def _wav_header(num_samples):
    data_size = num_samples * _BYTES_PER_SAMPLE
    byte_rate = _RATE * _BYTES_PER_SAMPLE
    block_align = _BYTES_PER_SAMPLE
    return struct.pack(
        "<4sI4s4sIHHIIHH4sI",
        b"RIFF", 36 + data_size, b"WAVE",
        b"fmt ", 16,
        1,
        _CHANNELS,
        _RATE,
        byte_rate,
        block_align,
        _BITS,
        b"data", data_size,
    )


def _free_internal_ram():
    """Tear down NimBLE and force-collect to release internal-RAM
    pressure ahead of an HTTPS upload.

    Background: the launcher (main.py) calls `bluetooth.BLE().active(True)`
    early so claude_buddy can advertise reliably. NimBLE on this build
    holds ~30 KB of internal RAM permanently while active. mbedTLS
    needs contiguous internal RAM (no PSRAM fallback in this firmware)
    for its working buffers during the TLS handshake; with NimBLE
    holding territory, even a 96 KB body OOMs at handshake time. We
    drop BLE here, get internal RAM back, and the launcher reactivates
    BLE on its next boot anyway."""
    try:
        import bluetooth
        ble = bluetooth.BLE()
        if ble.active():
            ble.active(False)
    except Exception as e:
        print("p2c: ble teardown warn:", e)
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
            print("p2c: wifi_event err:", e)
            return False
    except Exception as e:
        print("p2c: ensure_wifi err:", e)
        return False


def _record_to_file(kb):
    """Capture audio to ``_AUDIO_PATH`` using ``M5.Mic.recordWavFile``.

    Why we use recordWavFile rather than chunked record():
    on-device probing showed that ``M5.Mic.record(buf, rate, True)``
    returns essentially silent buffers (every sample == -8) on this
    UIFlow build — likely a binding mismatch with the underlying
    M5Unified API. ``recordWavFile`` does the capture inside the
    firmware and writes a properly-formed 16-bit PCM mono WAV file
    that Whisper transcribes correctly.

    Trade-off: recordWavFile is fixed-duration. There's no clean way
    to stop early and end up with a valid WAV (truncating the file
    leaves the header's data-size field wrong). So tap-to-stop is
    gone; we record for ``_MAX_SECONDS`` and the user just waits.

    Returns the number of audio samples captured (0 on error)."""
    try:
        os.remove(_AUDIO_PATH)
    except OSError:
        pass

    M5.Mic.begin()
    try:
        try:
            M5.Mic.setSampleRate(_RATE)
        except Exception as e:
            print("p2c: setSampleRate warn:", e)

        # Kick off the recording. recordWavFile is async — it returns
        # immediately and isRecording() reports completion.
        try:
            M5.Mic.recordWavFile(_AUDIO_PATH, _RATE, _MAX_SECONDS)
        except TypeError:
            # Fallback signature variants if the firmware uses a
            # different ordering. Empirically (path, rate, sec) is
            # what works on our build, but be defensive.
            try:
                M5.Mic.recordWavFile(_AUDIO_PATH, _MAX_SECONDS, _RATE)
            except Exception as e:
                print("p2c: recordWavFile err:", e)
                return 0

        # Drive the LCD heartbeat while the firmware records. Poll
        # isRecording every ~120 ms; bail if it runs long over the
        # expected duration (firmware may have failed silently).
        deadline = time.ticks_add(
            time.ticks_ms(), (_MAX_SECONDS + 2) * 1000,
        )
        last_phase = -1
        last_ms = 0
        while M5.Mic.isRecording():
            now = time.ticks_ms()
            if time.ticks_diff(now, deadline) > 0:
                # Force-stop a runaway recording.
                try:
                    M5.Mic.end()
                except Exception:
                    pass
                break
            if time.ticks_diff(now, last_ms) >= 120:
                # Phase derived from elapsed-ish time so the dot
                # walks at a steady pace regardless of firmware
                # cadence.
                phase = (now // 360) % _DOT_COUNT
                if phase != last_phase:
                    _draw_recording_dots(phase)
                    last_phase = phase
                last_ms = now
            # Honor Q/ESC even mid-recording — better to abort and
            # let the user retry than to wedge the device.
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
            print("p2c: mic.end warn:", e)

    try:
        size = os.stat(_AUDIO_PATH)[6]
    except OSError:
        return 0
    # Subtract 44-byte WAV header to get sample-count estimate.
    return max(0, (size - 44) // _BYTES_PER_SAMPLE)
    return samples_written


def _https_post_file_stream(url, file_path, headers, chunk_size=2048, timeout_s=60):
    """File-streamed HTTPS POST.

    The audio body never lives in a Python bytes object; we read it
    from disk in fixed-size chunks straight into a reusable buffer
    and write that to the SSL socket. Memory peak during upload is
    roughly ``chunk_size + response_buffer + TLS_state`` ≈ 35 KB.

    Critical detail confirmed by an on-device probe: kwargs DO work
    on ``ssl.wrap_socket`` on this UIFlow build (a previous TypeError
    we observed must have come from elsewhere). So SNI lands cleanly
    via ``server_hostname=host`` and Cloudflare routes the request.

    Returns ``(status, body_bytes)``.
    """
    import socket
    import ssl as _ssl

    if not url.startswith("https://"):
        raise RuntimeError("only https supported")
    rest = url[len("https://"):]
    slash = rest.find("/")
    if slash == -1:
        host_port, http_path = rest, "/"
    else:
        host_port, http_path = rest[:slash], rest[slash:]
    if ":" in host_port:
        host, port_str = host_port.split(":", 1)
        port = int(port_str)
    else:
        host, port = host_port, 443

    file_size = os.stat(file_path)[6]

    # Force a clean heap before mbedTLS allocates its working memory.
    gc.collect()
    gc.collect()

    addr = socket.getaddrinfo(host, port)[0][-1]
    s = socket.socket()
    try:
        s.settimeout(timeout_s)
    except Exception:
        pass
    s.connect(addr)
    ss = _ssl.wrap_socket(s, server_hostname=host)

    try:
        head = (
            "POST {} HTTP/1.1\r\n"
            "Host: {}\r\n"
            "User-Agent: m5-cardputer\r\n"
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

        # Read response — small JSON, cap at 8 KB.
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


def _post_reset():
    """Clear server-side conversation history for this device. Quick
    fire-and-forget; uses requests since the body is empty."""
    _free_internal_ram()
    import requests
    headers = {"x-device-secret": DEVICE_SECRET}
    try:
        r = requests.post(WORKER_RESET_URL, headers=headers, timeout=15)
        try:
            return r.status_code == 200
        finally:
            try:
                r.close()
            except Exception:
                pass
    except Exception as e:
        print("p2c: reset err:", e)
        return False


def _post_text(prompt):
    """POST a typed prompt to /ask-text. Returns the parsed JSON dict.
    Body is tiny so the OOM concern doesn't really apply, but we still
    free internal RAM first to keep behavior consistent."""
    _free_internal_ram()
    import json as _json
    body = _json.dumps({"prompt": prompt}).encode()
    gc.collect()

    import requests
    headers = {
        "content-type": "application/json",
        "x-device-secret": DEVICE_SECRET,
    }
    r = requests.post(WORKER_TEXT_URL, data=body, headers=headers, timeout=45)
    try:
        if r.status_code != 200:
            raise RuntimeError(
                "worker {}: {}".format(r.status_code, r.text[:120]),
            )
        return r.json()
    finally:
        try:
            r.close()
        except Exception:
            pass


def _post_recording():
    """Read the captured WAV and POST it. Returns the parsed JSON dict
    on success; raises on any failure (including an empty file).

    mbedTLS on this MicroPython build draws its working memory from
    internal RAM only, regardless of PSRAM availability. A few rounds
    of gc.collect() before opening the TLS connection meaningfully
    shrinks the heap fragmentation that otherwise OOMs us during the
    handshake."""
    try:
        size = os.stat(_AUDIO_PATH)[6]
    except OSError as e:
        raise RuntimeError("no audio file: {}".format(e))
    if size <= 44:
        raise RuntimeError("empty recording")

    _free_internal_ram()

    file_size = os.stat(_AUDIO_PATH)[6]
    _draw_uploading("uploading", "{} KB".format(file_size // 1024))

    headers = {
        "content-type": "audio/wav",
        "x-device-secret": DEVICE_SECRET,
    }
    _draw_uploading("transcribing", "speaking to Whisper")
    status, resp_body = _https_post_file_stream(
        WORKER_URL, _AUDIO_PATH, headers, chunk_size=2048, timeout_s=60,
    )
    gc.collect()
    _draw_uploading("got reply", "decoding")

    if status != 200:
        snippet = resp_body[:160].decode("utf-8", "replace")
        raise RuntimeError("worker {}: {}".format(status, snippet))
    import json as _json
    return _json.loads(resp_body)


# ---- MAIN -----------------------------------------------------------

def run():
    _set_font()
    if not _WORKER_BASE or not DEVICE_SECRET:
        _draw_error(
            "Not configured.\n"
            "Copy apps/config.example.py\nto apps/config.py\n"
            "and fill in WORKER_BASE\n+ DEVICE_SECRET."
        )
        kb = MatrixKeyboard()
        while True:
            kb.tick()
            if _is_exit(kb.get_key()):
                return
            time.sleep_ms(50)
    wifi_ok = _ensure_wifi()
    _draw_idle(wifi_ok)
    kb = MatrixKeyboard()
    time.sleep_ms(400)

    state = "idle"
    text_buf = ""
    cursor_on = True
    last_blink_ms = 0
    # Showing state: keep the result around so we can re-render at a
    # different scroll offset without a fresh API round-trip.
    last_transcript = ""
    last_response = ""
    scroll = 0

    try:
        while True:
            kb.tick()
            k = kb.get_key()

            # ESC always exits — but ONLY in non-typing states. In
            # typing mode ESC just returns to idle without leaving the
            # app, since the user might want to retry without a full
            # reboot.
            if state != "typing" and _is_exit(k):
                return

            if state == "idle":
                if _is_space(k):
                    state = "recording"
                    gc.collect()
                    _draw_recording_initial()
                    _draw_recording_dots(0)
                    try:
                        _record_to_file(kb)
                    except KeyboardInterrupt:
                        return
                    state = "uploading"
                    _draw_uploading()
                    try:
                        result = _post_recording()
                        last_transcript = result.get("transcript", "")
                        last_response = result.get("response", "")
                        scroll = 0
                        state = "showing"
                        _draw_result(last_transcript, last_response, scroll)
                    except Exception as e:
                        msg = str(e)[:200]
                        print("p2c: post err:", msg)
                        state = "error"
                        _draw_error(msg)
                    # Clean up the file regardless. Frees ~1 MB.
                    try:
                        os.remove(_AUDIO_PATH)
                    except OSError:
                        pass
                    gc.collect()

                elif _is_text_trigger(k):
                    state = "typing"
                    text_buf = ""
                    cursor_on = True
                    last_blink_ms = time.ticks_ms()
                    _draw_typing(text_buf, cursor_on)

                elif _is_new_chat(k):
                    cleared = _post_reset()
                    msg = "memory cleared" if cleared else "reset failed"
                    _draw_idle(wifi_ok, status_msg=msg)
                    time.sleep_ms(900)
                    _draw_idle(wifi_ok)

            elif state == "typing":
                # ESC in typing mode → back to idle (NOT exit).
                if k is not None and isinstance(k, int) and k == 0x1B:
                    state = "idle"
                    text_buf = ""
                    wifi_ok = _ensure_wifi()
                    _draw_idle(wifi_ok)
                elif _is_enter(k):
                    if text_buf.strip():
                        state = "uploading"
                        _draw_uploading()
                        try:
                            result = _post_text(text_buf.strip())
                            last_transcript = result.get("transcript", "")
                            last_response = result.get("response", "")
                            scroll = 0
                            state = "showing"
                            _draw_result(last_transcript, last_response, scroll)
                        except Exception as e:
                            msg = str(e)[:200]
                            print("p2c: text-post err:", msg)
                            state = "error"
                            _draw_error(msg)
                        text_buf = ""
                        gc.collect()
                elif _is_backspace(k):
                    if text_buf:
                        text_buf = text_buf[:-1]
                        _draw_typing(text_buf, cursor_on)
                else:
                    ch = _printable_char(k)
                    if ch is not None and len(text_buf) < 240:
                        text_buf += ch
                        _draw_typing(text_buf, cursor_on)

                # Blink the caret on a 500 ms cycle. ONLY redraw if
                # we're still in typing state — Enter triggers a state
                # change to uploading/showing/error inside this branch
                # and we must not overwrite the result/error screen on
                # the way out.
                if state == "typing":
                    now = time.ticks_ms()
                    if time.ticks_diff(now, last_blink_ms) >= 500:
                        cursor_on = not cursor_on
                        last_blink_ms = now
                        _draw_typing(text_buf, cursor_on)

            elif state == "showing":
                if _is_new_chat(k):
                    cleared = _post_reset()
                    state = "idle"
                    wifi_ok = _ensure_wifi()
                    _draw_idle(
                        wifi_ok,
                        status_msg="memory cleared" if cleared else "reset failed",
                    )
                    time.sleep_ms(900)
                    _draw_idle(wifi_ok)
                    time.sleep_ms(40)
                    continue
                intent = _scroll_intent(k)
                if intent is not None:
                    # Recompute layout each scroll keypress — it's cheap
                    # (just text-width measurements) and lets us keep
                    # exactly one source of truth (_result_layout) for
                    # scroll bounds.
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
                        _draw_result(last_transcript, last_response, scroll)
                elif _is_space(k):
                    state = "idle"
                    wifi_ok = _ensure_wifi()
                    _draw_idle(wifi_ok)
                elif _is_text_trigger(k):
                    state = "typing"
                    text_buf = ""
                    cursor_on = True
                    last_blink_ms = time.ticks_ms()
                    _draw_typing(text_buf, cursor_on)

            elif state == "error":
                if _is_space(k):
                    state = "idle"
                    wifi_ok = _ensure_wifi()
                    _draw_idle(wifi_ok)
                elif _is_text_trigger(k):
                    state = "typing"
                    text_buf = ""
                    cursor_on = True
                    last_blink_ms = time.ticks_ms()
                    _draw_typing(text_buf, cursor_on)
                elif _is_new_chat(k):
                    cleared = _post_reset()
                    state = "idle"
                    wifi_ok = _ensure_wifi()
                    _draw_idle(
                        wifi_ok,
                        status_msg="memory cleared" if cleared else "reset failed",
                    )
                    time.sleep_ms(900)
                    _draw_idle(wifi_ok)

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
