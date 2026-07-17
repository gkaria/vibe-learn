"""Upload the buddy .py files onto a UIFlow 2.0 M5Stack over USB-serial.

Usage:
    python push.py --port /dev/cu.usbserial-XXXX

The device already has MicroPython + UIFlow 2.0 running (flashed by
the m5-onboard skill). We just copy our sources into /flash/
so that `main.py` takes over on the next boot.

Transfer mechanism: paste-mode REPL. We send a small helper that
opens a file for write, then base64-chunk the source bytes in via
`ubinascii.a2b_base64` and append. This is slow (~3 KB/s) but needs
nothing on the device that isn't in stock MicroPython, and it
survives wedged UIFlow apps because we Ctrl-C into the REPL first.

A faster alternative is `mpremote`, but that requires installing an
extra package and adds a debugging surface. Keep this script in the
dependency-free lane; switch to mpremote later if the transfer time
becomes a problem.
"""

from __future__ import annotations

import argparse
import base64
import os
import sys
import time

try:
    import serial
except ImportError:
    sys.stderr.write("pyserial not installed. Try: pip install pyserial\n")
    raise


# Default file set when --files isn't passed. Lists every *.py
# under buddy/device/ (root + apps/) that ships on the device. The
# previous list referenced "buddy_ui.py" — that module was renamed
# to buddy_ui_cp.py during the Cardputer port and the rename never
# made it here, so a default invocation immediately failed with
# "no such file or directory".
DEFAULT_FILES = [
    "main.py",
    "buddy_ble.py",
    "buddy_ui_cp.py",
    "buddy_state.py",
    "buddy_chars.py",
    "buddy_protocol.py",
    "burst_frames.py",
    "wifi_event.py",
    "apps/claude_buddy.py",
    "apps/hello_cardputer.py",
    "apps/snake.py",
]

CHUNK_BYTES = 512  # source bytes per paste-mode write


def _drain(s: serial.Serial, wait: float = 0.2) -> bytes:
    time.sleep(wait)
    buf = b""
    while s.in_waiting:
        buf += s.read(s.in_waiting)
        time.sleep(0.03)
    return buf


def _interrupt(s: serial.Serial) -> None:
    for _ in range(4):
        s.write(b"\x03")
        time.sleep(0.05)
    s.write(b"\r\n")
    _drain(s, wait=0.3)


def _hard_reset(s: serial.Serial) -> None:
    s.setDTR(False)
    s.setRTS(True)
    time.sleep(0.1)
    s.setRTS(False)


def _paste(s: serial.Serial, script: str, settle: float = 0.3) -> str:
    s.write(b"\x05")  # Ctrl-E (enter paste)
    time.sleep(0.1)
    _drain(s, wait=0.1)
    for line in script.splitlines():
        s.write(line.encode() + b"\r\n")
        time.sleep(0.005)
    s.write(b"\x04")  # Ctrl-D (execute)
    raw = _drain(s, wait=settle)
    return raw.decode("utf-8", errors="replace")


def _upload_file(s: serial.Serial, src_path: str, dest_name: str) -> None:
    """Copy src_path → /flash/<dest_name> on the device.

    Handles a single subdirectory in dest_name (e.g. "apps/foo.py")
    by mkdir-ing it on the device first if it doesn't exist. We only
    support one level because that's all the bundle layout uses;
    nested layouts (apps/sub/foo.py) would need to walk the path.
    """
    with open(src_path, "rb") as f:
        data = f.read()

    # Open the destination once, then append base64 chunks. Keeping
    # the file handle alive across paste-mode blocks works because
    # paste-mode runs each Ctrl-D block in the same REPL globals
    # namespace.
    head_lines = ["import ubinascii"]
    if "/" in dest_name:
        sub = dest_name.rsplit("/", 1)[0]
        head_lines.append("import uos")
        head_lines.append("try: uos.stat('/flash/{}')".format(sub))
        head_lines.append("except OSError: uos.mkdir('/flash/{}')".format(sub))
    head_lines.append('fp = open("/flash/{}", "wb")'.format(dest_name))
    head = "\n".join(head_lines) + "\n"
    out = _paste(s, head, settle=0.2)
    # Check only for Traceback, not "Error", because the echoed script
    # contains "except OSError:" which would produce a false positive.
    if "Traceback" in out:
        raise RuntimeError("failed to open dest file:\n" + out)

    total = len(data)
    sent = 0
    while sent < total:
        chunk = data[sent : sent + CHUNK_BYTES]
        b64 = base64.b64encode(chunk).decode("ascii")
        # Use a fresh paste-mode block per chunk. A single block with
        # thousands of lines of base64 occasionally gets silently
        # truncated on the RX side; chunking keeps each paste small.
        body = 'fp.write(ubinascii.a2b_base64("{}"))\n'.format(b64)
        out = _paste(s, body, settle=0.05)
        if "Error" in out or "Traceback" in out:
            raise RuntimeError("chunk write failed at offset {}:\n{}".format(sent, out))
        sent += len(chunk)
        sys.stderr.write("\r  {}: {}/{} bytes".format(dest_name, sent, total))
        sys.stderr.flush()
    sys.stderr.write("\n")

    tail = "fp.close()\nprint('WROTE', '{}')\n".format(dest_name)
    out = _paste(s, tail, settle=0.2)
    if "WROTE {}".format(dest_name) not in out:
        raise RuntimeError("close/verify failed:\n" + out)


def main() -> int:
    ap = argparse.ArgumentParser(description="Push Claude Buddy sources to an M5Stack.")
    ap.add_argument("--port", required=True)
    ap.add_argument(
        "--src",
        default=os.path.join(os.path.dirname(__file__), "..", "device"),
        help="Directory holding the .py sources.",
    )
    ap.add_argument(
        "--files",
        nargs="*",
        default=DEFAULT_FILES,
        help="Files to upload (basenames under --src).",
    )
    ap.add_argument(
        "--no-reset",
        action="store_true",
        help="Skip hard-reset after upload (leave device at REPL).",
    )
    args = ap.parse_args()

    src_dir = os.path.abspath(args.src)
    for name in args.files:
        full = os.path.join(src_dir, name)
        if not os.path.isfile(full):
            sys.stderr.write("missing source: {}\n".format(full))
            return 2

    s = serial.Serial(args.port, 115200, timeout=1.0)
    try:
        _hard_reset(s)
        # Give UIFlow's init a chance to settle before we interrupt,
        # otherwise its startup tasks spam the REPL during our paste.
        time.sleep(2.0)
        _interrupt(s)
        _drain(s, wait=0.3)

        for name in args.files:
            src_path = os.path.join(src_dir, name)
            sys.stderr.write("uploading {}...\n".format(name))
            _upload_file(s, src_path, name)

        if not args.no_reset:
            sys.stderr.write("rebooting device so main.py runs...\n")
            _paste(s, "import machine; machine.reset()\n", settle=0.5)
    finally:
        s.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
