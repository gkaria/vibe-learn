"""vibe-deck device config — copy to ``config.py`` and fill in.

The Voice Center app loads these at import time. ``config.py`` is
gitignored so your secret never leaves the device. See deck/README.md.
"""

# Your Mac's LAN address + gateway port. Plain HTTP on the home LAN;
# an https:// tunnel URL also works. No trailing slash.
#   Find your Mac's IP: System Settings → Wi-Fi → Details, or
#   `ipconfig getifaddr en0`.
GATEWAY_URL = "http://192.168.1.10:8756"

# Must match GATEWAY_SECRET in ~/.vibe-deck/env on the Mac.
GATEWAY_SECRET = ""

# Target selected at boot: "claude" | "chatgpt" | "learn"
DEFAULT_TARGET = "claude"
