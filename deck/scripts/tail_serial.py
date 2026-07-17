"""Tail the device serial output for a few seconds, print what we saw.

Used as a smoke check right after push.py — we want to see the Buddy
banner ('Claude Buddy up as Claude_XXXXXX') without an exception
trace before it.
"""

from __future__ import annotations

import argparse
import sys
import time

import serial


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True)
    ap.add_argument("--seconds", type=float, default=8.0)
    args = ap.parse_args()

    s = serial.Serial(args.port, 115200, timeout=0.2)
    try:
        deadline = time.time() + args.seconds
        buf = b""
        while time.time() < deadline:
            if s.in_waiting:
                buf += s.read(s.in_waiting)
            time.sleep(0.05)
    finally:
        s.close()

    text = buf.decode("utf-8", errors="replace")
    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
