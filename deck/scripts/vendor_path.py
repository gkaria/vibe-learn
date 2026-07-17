"""Make pyserial importable for the serial scripts.

The cardputer-claude-os fork vendored pyserial under scripts/vendor/ so
the push tools worked without any pip install. That vendor tree wasn't
imported into deck/; here we prefer a local vendor/ dir if one exists
and otherwise fall back to whatever environment python is running
(e.g. ~/.vibe-deck/venv with pyserial installed).
"""

import os
import sys


def ensure_on_syspath() -> None:
    vendor = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor")
    if os.path.isdir(vendor) and vendor not in sys.path:
        sys.path.insert(0, vendor)
