#!/usr/bin/env python3
"""Writes a phase-completion marker + a UTC timestamp to .feanor/state/status.json.

Two markers exist, and they answer different questions:

  scaffolded   — /scaffold created this source tree. Distinguishes a greenfield
                 project that Feanor built from a brownfield project whose source
                 predates Feanor. Without it, "backend/ exists" is ambiguous and
                 the brownfield /standardize gate fires on greenfield projects.
  standardized — /standardize's compliance audit passed clean on pre-existing
                 source. Only written on a clean pass.

Usage:
  write-state-marker.py scaffolded [path/to/status.json]
  write-state-marker.py standardized [path/to/status.json]

Called by agents/architect-agent.md (/scaffold) and
workflows/brownfield-standardize.md (/standardize).
"""

import json
import os
import sys
from datetime import datetime, timezone

MARKERS = ("scaffolded", "standardized")

if len(sys.argv) < 2 or sys.argv[1] not in MARKERS:
    print(f"usage: {os.path.basename(sys.argv[0])} {{{'|'.join(MARKERS)}}} [status.json]", file=sys.stderr)
    sys.exit(1)

marker = sys.argv[1]
path = sys.argv[2] if len(sys.argv) > 2 else ".feanor/state/status.json"

if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        status = json.load(f)
else:
    status = {}

status[marker] = True
status[f"{marker}_at"] = datetime.now(timezone.utc).isoformat()

os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
with open(path, "w", encoding="utf-8") as f:
    json.dump(status, f, indent=2)

print(f"Wrote {marker}:true to {path}")
