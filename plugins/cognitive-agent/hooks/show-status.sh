#!/bin/bash
set -euo pipefail

_find_project_root() {
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" && -f "${CLAUDE_PROJECT_DIR}/pipeline/mcp_server.py" ]]; then
    echo "$CLAUDE_PROJECT_DIR"; return
  fi
  local base="${CLAUDE_PROJECT_DIR:-$PWD}"
  if [[ -f "$base/pipeline/mcp_server.py" ]]; then
    echo "$base"; return
  fi
  for d in "$base"/*/; do
    [[ -f "${d}pipeline/mcp_server.py" ]] && { echo "${d%/}"; return; }
  done
  echo "${CLAUDE_PROJECT_DIR:-$PWD}"
}
COGNITIVE_DIR="$(_find_project_root)/.cognitive"
ACTIVE_FLAG="$COGNITIVE_DIR/.active"
SESSION_INDEX="$COGNITIVE_DIR/session.index.md"

if [[ ! -f "$ACTIVE_FLAG" ]]; then
  exit 0
fi

if [[ ! -f "$SESSION_INDEX" ]]; then
  exit 0
fi

EXCERPT_COUNT=$(wc -l < "$SESSION_INDEX" | tr -d ' ')
echo "💡 Cognitive Agent active — ${EXCERPT_COUNT} excerpt(s) in profile"
