#!/usr/bin/env python3
"""Compile pager.py to .mpy bytecode and upload to /flash/apps/ on the
connected Cardputer.

Why .mpy: the source-form pager.py (~31 KB) is large enough that
parsing it during `import pager` exhausts the launcher-leftover heap
on this UIFlow build, hard-resetting the chip. Pre-compiled bytecode
loads without parsing -- ~11 KB on disk and effectively free at import.

Usage:
    python3 buddy/scripts/push_pager_mpy.py --port /dev/cu.usbmodem2101

Requires `mpy-cross` (Python wrapper around the MicroPython cross
compiler). Install with:
    pip3 install --user --break-system-packages mpy-cross
The mpy-cross version must match the device firmware's mpy ABI.
For UIFlow 2.0 on Cardputer-Adv that is mpy v6.3 (MicroPython 1.27).
"""

from __future__ import annotations

import argparse
import base64
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
SRC = REPO / "buddy" / "device" / "apps" / "pager.py"
DEST = "/flash/apps/pager.mpy"
LEGACY_PY = "/flash/apps/pager.py"

sys.path.insert(0, str(REPO / ".claude" / "skills" / "m5-onboard" / "scripts"))


def compile_mpy(src: Path) -> Path:
    """Invoke mpy-cross via its Python entrypoint. Returns the .mpy
    path; aborts on compile failure."""
    try:
        import mpy_cross  # type: ignore
    except ImportError:
        sys.exit("mpy-cross not installed. Run: pip3 install --user --break-system-packages mpy-cross")

    out_dir = Path(tempfile.mkdtemp(prefix="pager-mpy-"))
    out_path = out_dir / "pager.mpy"
    # mpy_cross.run() spawns the bundled mpy-cross binary internally; it
    # only accepts the documented CLI flags as a list of strings.
    rc = mpy_cross.run("-O2", str(src), "-o", str(out_path)).wait()
    if rc != 0 or not out_path.exists():
        sys.exit(f"mpy-cross exited with status {rc}")
    return out_path


def upload(port: str, mpy_path: Path) -> None:
    import mpy_repl as r  # type: ignore

    data = mpy_path.read_bytes()
    print(f"src bytes: {len(data)}")
    b64 = base64.b64encode(data).decode()
    chunk = 1024
    parts = [b64[i : i + chunk] for i in range(0, len(b64), chunk)]
    print(f"chunks: {len(parts)} of {chunk}B b64")

    s = r.open_port(port)
    try:
        r.interrupt_to_repl(s)
        if s.in_waiting:
            s.read(s.in_waiting)

        out = r.paste_exec(
            s,
            (
                "import os, ubinascii\n"
                'try: os.remove("' + DEST + '")\n'
                "except OSError: pass\n"
                'f = open("' + DEST + '", "wb")\n'
                'print("OPEN_OK")\n'
            ),
            settle=2,
        )
        text = _to_str(out)
        if "OPEN_OK" not in text:
            sys.exit("open failed:\n" + text)

        for i, p in enumerate(parts):
            script = f'f.write(ubinascii.a2b_base64("{p}"))\nprint("CHUNK_{i+1}/{len(parts)}")\n'
            out = r.paste_exec(s, script, settle=1)
            text = _to_str(out)
            if "CHUNK" not in text:
                sys.exit(f"chunk {i+1} failed:\n{text}")
            sys.stdout.write(f"\r  chunk {i+1}/{len(parts)}")
            sys.stdout.flush()
        print()

        out = r.paste_exec(
            s,
            (
                "f.close()\n"
                "import os\n"
                'try: os.remove("' + LEGACY_PY + '")\n'
                "except OSError: pass\n"
                'print("DONE size=", os.stat("' + DEST + '")[6])\n'
            ),
            settle=2,
        )
        print(_to_str(out).strip().splitlines()[-1])

        # Soft-reboot so the launcher comes up fresh on the new bytecode.
        s.write(b"import machine; machine.reset()\r\n")
        s.flush()
        print("device rebooted into launcher")
    finally:
        s.close()


def _to_str(out) -> str:
    return out if isinstance(out, str) else out.decode("utf-8", "replace")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--port", required=True)
    ap.add_argument("--src", default=str(SRC), help="path to pager.py")
    args = ap.parse_args()

    src = Path(args.src)
    if not src.exists():
        sys.exit(f"source not found: {src}")
    mpy_path = compile_mpy(src)
    print(f"compiled {src.name} -> {mpy_path} ({mpy_path.stat().st_size}B)")
    upload(args.port, mpy_path)


if __name__ == "__main__":
    main()
