#!/usr/bin/env python3
"""Compile a deck device app to .mpy bytecode and upload it to
/flash/apps/ on the connected Cardputer. Generalized from the fork's
push_pager_mpy.py.

Why .mpy: apps past ~25 KB of source exhaust the launcher-leftover heap
during import-time parsing on this UIFlow build, hard-resetting the
chip. Pre-compiled bytecode loads without parsing.

Usage:
    python3 deck/scripts/push_app_mpy.py --port /dev/cu.usbmodem2101
    python3 deck/scripts/push_app_mpy.py --port ... --app voice_center \
        --config deck/device/config.py   # also push device config

Requires `mpy-cross` matching the device firmware's mpy ABI (UIFlow 2.0
on Cardputer-Adv = mpy v6.3):
    pip3 install --user --break-system-packages mpy-cross
"""

from __future__ import annotations

import argparse
import base64
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEVICE_DIR = HERE.parent / "device"

sys.path.insert(0, str(HERE))


def compile_mpy(src: Path, name: str) -> Path:
    try:
        import mpy_cross  # type: ignore
    except ImportError:
        sys.exit(
            "mpy-cross not installed. Run: "
            "pip3 install --user --break-system-packages mpy-cross"
        )

    out_dir = Path(tempfile.mkdtemp(prefix=f"{name}-mpy-"))
    out_path = out_dir / f"{name}.mpy"
    rc = mpy_cross.run("-O2", str(src), "-o", str(out_path)).wait()
    if rc != 0 or not out_path.exists():
        sys.exit(f"mpy-cross exited with status {rc}")
    return out_path


def _to_str(out) -> str:
    return out if isinstance(out, str) else out.decode("utf-8", "replace")


def _write_file(s, r, dest: str, data: bytes) -> None:
    """Stream bytes to a device path in base64 chunks over the REPL."""
    b64 = base64.b64encode(data).decode()
    chunk = 1024
    parts = [b64[i : i + chunk] for i in range(0, len(b64), chunk)]
    print(f"{dest}: {len(data)}B in {len(parts)} chunks")

    out = r.paste_exec(
        s,
        (
            "import os, ubinascii\n"
            f'try: os.remove("{dest}")\n'
            "except OSError: pass\n"
            f'f = open("{dest}", "wb")\n'
            'print("OPEN_OK")\n'
        ),
        settle=2,
    )
    if "OPEN_OK" not in _to_str(out):
        sys.exit("open failed:\n" + _to_str(out))

    for i, p in enumerate(parts):
        script = (
            f'f.write(ubinascii.a2b_base64("{p}"))\n'
            f'print("CHUNK_{i + 1}/{len(parts)}")\n'
        )
        out = r.paste_exec(s, script, settle=1)
        if "CHUNK" not in _to_str(out):
            sys.exit(f"chunk {i + 1} failed:\n{_to_str(out)}")
        sys.stdout.write(f"\r  chunk {i + 1}/{len(parts)}")
        sys.stdout.flush()
    print()

    out = r.paste_exec(
        s,
        f'f.close()\nimport os\nprint("DONE size=", os.stat("{dest}")[6])\n',
        settle=2,
    )
    print(_to_str(out).strip().splitlines()[-1])


def upload(port: str, app: str, mpy_path: Path, config: Path | None) -> None:
    import mpy_repl as r  # type: ignore

    s = r.open_port(port)
    try:
        r.interrupt_to_repl(s)
        if s.in_waiting:
            s.read(s.in_waiting)

        _write_file(s, r, f"/flash/apps/{app}.mpy", mpy_path.read_bytes())
        # Remove any stale source-form copy so the launcher doesn't list
        # the app twice or import the slow path.
        r.paste_exec(
            s,
            f'import os\ntry: os.remove("/flash/apps/{app}.py")\n'
            "except OSError: pass\n",
            settle=1,
        )
        if config is not None:
            _write_file(s, r, "/flash/apps/config.py", config.read_bytes())

        s.write(b"import machine; machine.reset()\r\n")
        s.flush()
        print("device rebooted into launcher")
    finally:
        s.close()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--port", required=True)
    ap.add_argument("--app", default="voice_center")
    ap.add_argument("--src", default=None, help="defaults to deck/device/<app>.py")
    ap.add_argument(
        "--config", default=None,
        help="optional path to a config.py to push to /flash/apps/config.py",
    )
    args = ap.parse_args()

    src = Path(args.src) if args.src else DEVICE_DIR / f"{args.app}.py"
    if not src.exists():
        sys.exit(f"source not found: {src}")
    config = Path(args.config) if args.config else None
    if config is not None and not config.exists():
        sys.exit(f"config not found: {config}")

    mpy_path = compile_mpy(src, args.app)
    print(f"compiled {src.name} -> {mpy_path} ({mpy_path.stat().st_size}B)")
    upload(args.port, args.app, mpy_path, config)


if __name__ == "__main__":
    main()
