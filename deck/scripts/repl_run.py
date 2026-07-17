"""Interrupt to REPL and run a snippet; print the output.

Thin wrapper around paste-mode for poking at the device during
development. Prints both what was sent and what came back so the
conversation is obvious.
"""

from __future__ import annotations

import argparse
import sys
import time

import serial


def _drain(s, wait=0.2):
    time.sleep(wait)
    buf = b""
    while s.in_waiting:
        buf += s.read(s.in_waiting)
        time.sleep(0.03)
    return buf


def _interrupt(s):
    for _ in range(5):
        s.write(b"\x03")
        time.sleep(0.05)
    s.write(b"\r\n")
    _drain(s, wait=0.3)


def _paste(s, script, settle=0.5):
    s.write(b"\x05")
    time.sleep(0.1)
    _drain(s, wait=0.1)
    for line in script.splitlines():
        s.write(line.encode() + b"\r\n")
        time.sleep(0.005)
    s.write(b"\x04")
    return _drain(s, wait=settle).decode("utf-8", errors="replace")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True)
    ap.add_argument("--script", required=True, help="MicroPython source to run")
    ap.add_argument("--settle", type=float, default=1.0)
    args = ap.parse_args()

    s = serial.Serial(args.port, 115200, timeout=1.0)
    try:
        _interrupt(s)
        out = _paste(s, args.script, settle=args.settle)
        sys.stdout.write(out)
    finally:
        s.close()


if __name__ == "__main__":
    main()
