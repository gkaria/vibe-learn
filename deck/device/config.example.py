"""Push-to-Claude device config — copy to ``config.py`` and fill in.

The Push-to-Claude app loads ``WORKER_BASE`` and ``DEVICE_SECRET``
from this module at import time. ``config.py`` is gitignored so your
secret never leaves the device. See ``worker/README.md`` for how to
deploy your own Cloudflare Worker relay and where to get these
values.
"""

# Base URL of YOUR deployed Cloudflare Worker, e.g.
#   "https://push-to-claude.<your-subdomain>.workers.dev"
# No trailing slash; the app appends "/ask", "/ask-text", "/reset".
WORKER_BASE = ""

# Shared secret between this device and the Worker. Must match the
# DEVICE_SECRET you set on the Worker via:
#   wrangler secret put DEVICE_SECRET
# Generate one with: ``openssl rand -base64 32`` (or any random 32+ char string).
DEVICE_SECRET = ""
