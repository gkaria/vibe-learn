"""Shared helpers for talking to a MicroPython REPL on an M5Stack over USB-serial.

These wrap the patterns that were painful to discover the hard way:
- The ESP32 auto-reset sequence that UIFlow boots cleanly from
- Paste mode for multi-line blocks (the REPL mishandles indentation
  when you send compound statements line-by-line)
- Boot-log capture with a sentinel so you know when the device is idle
"""

from __future__ import annotations

import sys
import time

# Pull the vendored pyserial onto sys.path before the import below.
# See scripts/vendor_path.py for the why.
import vendor_path
vendor_path.ensure_on_syspath()

try:
    import serial
except ImportError:
    sys.stderr.write("pyserial not installed. Try: pip install pyserial\n")
    raise


REPL_BAUD = 115200


def open_port(port: str, baud: int = REPL_BAUD, timeout: float = 1.0) -> "serial.Serial":
    return serial.Serial(port, baud, timeout=timeout)


def hard_reset(s: "serial.Serial") -> None:
    """Pulse the ESP32 auto-reset circuit via DTR/RTS.

    DTR drives GPIO0 through an inverting transistor, RTS drives EN.
    Holding DTR false + pulsing RTS true->false gives a clean boot into
    the normal app (not bootloader), which is what UIFlow wants.

    Only works on UART-bridge devices (CH9102, CP210x). On ESP32-S3/C3
    native USB (no bridge chip), DTR/RTS are not wired to EN/GPIO0 and
    this call has no effect. Use repl_reset() for those devices.
    """
    s.setDTR(False)
    s.setRTS(True)
    time.sleep(0.1)
    s.setRTS(False)


def repl_reset(s: "serial.Serial") -> None:
    """Reset the device by sending machine.reset() through the REPL.

    Works on any MicroPython device regardless of USB topology — in
    particular on ESP32-S3/C3 native USB where DTR/RTS have no effect.
    The port will close momentarily as the device reboots; callers
    should call wait_for_boot() afterwards if they need the REPL back.
    """
    interrupt_to_repl(s)
    s.write(b"import machine; machine.reset()\r\n")
    time.sleep(0.1)


def drain(s: "serial.Serial", wait: float = 0.2, chunk: int = 8192) -> bytes:
    time.sleep(wait)
    buf = b""
    while s.in_waiting:
        buf += s.read(min(s.in_waiting, chunk))
        time.sleep(0.05)
    return buf


def interrupt_to_repl(s: "serial.Serial", attempts: int = 5) -> bytes:
    """Send Ctrl-C a few times to break out of whatever is running
    and land at a friendly >>> prompt. Returns any output seen."""
    for _ in range(attempts):
        s.write(b"\x03")
        time.sleep(0.05)
    s.write(b"\r\n")
    return drain(s, wait=0.3)


def paste_exec(s: "serial.Serial", script: str, settle: float = 0.5) -> bytes:
    """Execute a multi-line script via the REPL's paste mode.

    Paste mode (Ctrl-E) disables auto-indent and line-level parsing;
    Ctrl-D runs the buffered block as a single unit. This is the only
    reliable way to send try/except, def, class, etc. without the REPL
    getting confused about indentation across line boundaries.

    Paste mode also echoes each line back as we send it. To keep the
    returned bytes limited to the script's actual output, we insert a
    known sentinel line (`print("__BEGIN__")`) at the top and strip
    everything before it in the response.
    """
    s.write(b"\x05")  # Ctrl-E
    time.sleep(0.1)
    drain(s, wait=0.1)
    sentinel = "__BEGIN__"
    body = f'print("{sentinel}")\n' + script
    for line in body.splitlines():
        s.write(line.encode() + b"\r\n")
        time.sleep(0.01)
    s.write(b"\x04")  # Ctrl-D
    raw = drain(s, wait=settle)
    text = raw.decode("utf-8", errors="replace")
    # Strip everything up to and including the first sentinel line.
    # There are two occurrences: the echo of the print() call and the
    # actual output of running it. We want to drop up through the
    # second (the output) so only post-sentinel prints remain.
    idx = 0
    for _ in range(2):
        found = text.find(sentinel, idx)
        if found < 0:
            break
        # Advance past the newline following this occurrence.
        nl = text.find("\n", found)
        idx = nl + 1 if nl >= 0 else found + len(sentinel)
    return text[idx:].encode("utf-8", errors="replace")


def wait_for_boot(
    s: "serial.Serial",
    sentinel: bytes = b">>>",
    timeout: float = 15.0,
) -> bytes:
    """Read from the port until we see the REPL prompt (or timeout).

    UIFlow 2.0 prints a lot before settling; we just want to know the
    app has finished its init and is accepting input.
    """
    deadline = time.time() + timeout
    buf = b""
    while time.time() < deadline:
        if s.in_waiting:
            buf += s.read(s.in_waiting)
            if sentinel in buf:
                return buf
        else:
            time.sleep(0.05)
    return buf


def exec_and_capture(
    s: "serial.Serial",
    script: str,
    settle: float = 0.5,
) -> str:
    """Paste a script, decode the REPL echo, and return it as text.

    Caller is responsible for parsing the echo; this just gives you the
    bytes after the final Ctrl-D in a convenient form.
    """
    interrupt_to_repl(s)
    raw = paste_exec(s, script, settle=settle)
    return raw.decode("utf-8", errors="replace")


def strip_paste_echo(text: str) -> str:
    """Remove MicroPython's paste-mode line echo from captured output.

    In paste mode the REPL echoes each incoming line prefixed with
    "=== "; those lines repeat the script text back and are useless
    when we only want the print output. Also drops trailing `>>>`
    prompt lines.
    """
    out = []
    for line in text.splitlines():
        if line.startswith("=== "):
            continue
        stripped = line.strip()
        if stripped in (">>>", "==="):
            continue
        out.append(line)
    return "\n".join(out)


def collect_until(
    s: "serial.Serial",
    initial: str,
    sentinel: str,
    timeout: float = 20.0,
    poll: float = 0.3,
) -> str:
    """Keep draining until `sentinel` appears or `timeout` elapses.

    Some long-running scripts (large file writes, NVS commits, board
    reset waits) print their progress over several seconds.
    `exec_and_capture`'s single settle delay isn't enough; callers
    should print a sentinel at the end of their script and then pass
    it here to wait for completion.
    """
    buf = initial
    deadline = time.time() + timeout
    while sentinel not in buf and time.time() < deadline:
        time.sleep(poll)
        buf += drain(s, wait=0.1).decode("utf-8", errors="replace")
    return buf
