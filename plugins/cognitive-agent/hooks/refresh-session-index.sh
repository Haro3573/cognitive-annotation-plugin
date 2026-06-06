#!/bin/bash
set -euo pipefail

# Refresh session_collection/raw/sessions.json at session start.
# Self-contained — no pipeline package required.

OUTPUT_DIR="${CLAUDE_PROJECT_DIR}/session_collection/raw"

python3 - "$OUTPUT_DIR" <<'PYEOF'
import sys, json, datetime
from pathlib import Path

output_dir = Path(sys.argv[1])
output_dir.mkdir(parents=True, exist_ok=True)

projects_root = Path.home() / ".claude" / "projects"
projects = {}
if projects_root.is_dir():
    for d in sorted(projects_root.iterdir()):
        if not d.is_dir():
            continue
        files = sorted(f.name for f in d.iterdir() if f.suffix == ".jsonl" and f.is_file())
        if files:
            projects[d.name] = files

index = {"updated_at": datetime.datetime.utcnow().isoformat() + "Z", "projects": projects}
(output_dir / "sessions.json").write_text(json.dumps(index, indent=2))
PYEOF
