#!/bin/bash
set -euo pipefail

ACTION="${1:-}"

# Resolve project root: prefer $CLAUDE_PROJECT_DIR (hook context);
# fall back to searching $PWD and one level of subdirs for the project marker.
_find_project_root() {
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    echo "$CLAUDE_PROJECT_DIR"; return
  fi
  if [[ -f "$PWD/pipeline/mcp_server.py" ]]; then
    echo "$PWD"; return
  fi
  for d in "$PWD"/*/; do
    [[ -f "${d}pipeline/mcp_server.py" ]] && { echo "${d%/}"; return; }
  done
  echo "$PWD"
}
COGNITIVE_DIR="$(_find_project_root)/.cognitive"
ACTIVE_FLAG="$COGNITIVE_DIR/.active"

case "$ACTION" in
  start)
    if [[ ! -f "$COGNITIVE_DIR/session.json" ]]; then
      echo "❌ No cognitive profile found at $COGNITIVE_DIR/session.json" >&2
      echo "" >&2
      echo "   Run the DB Block pipeline first:" >&2
      echo "   Mention a .jsonl session file in your prompt — Claude detects it automatically." >&2
      exit 1
    fi
    mkdir -p "$COGNITIVE_DIR"
    touch "$ACTIVE_FLAG"
    EXCERPT_COUNT=$(wc -l < "$COGNITIVE_DIR/session.index.md" 2>/dev/null | tr -d ' ')
    echo "✓ Cognitive agent activated — ${EXCERPT_COUNT} excerpt(s) in profile"
    echo "  A 💡 cognitive insight will appear after each AI response."
    echo "  To deactivate: /cognitive-agent:stop"
    ;;
  stop)
    if [[ -f "$ACTIVE_FLAG" ]]; then
      rm -f "$ACTIVE_FLAG"
      echo "Cognitive agent deactivated."
    else
      echo "Cognitive agent is not active."
    fi
    ;;
  *)
    echo "Usage: toggle.sh [start|stop]" >&2
    exit 1
    ;;
esac
