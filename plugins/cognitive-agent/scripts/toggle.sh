#!/bin/bash
set -euo pipefail

ACTION="${1:-}"
COGNITIVE_DIR="${CLAUDE_PROJECT_DIR}/.cognitive"
DISABLED_FLAG="$COGNITIVE_DIR/.disabled"

case "$ACTION" in
  stop)
    mkdir -p "$COGNITIVE_DIR"
    echo "${CLAUDE_CODE_SESSION_ID:-}" > "$DISABLED_FLAG"
    echo "Cognitive agent paused for this session."
    echo "Suggestions resume automatically in the next Claude Code session."
    echo "To re-enable now: /cognitive-agent:start"
    ;;
  start)
    if [[ -f "$DISABLED_FLAG" ]]; then
      rm -f "$DISABLED_FLAG"
      echo "Cognitive agent re-enabled."
    else
      echo "Cognitive agent is already active (no disabled flag found)."
    fi
    if [[ ! -f "$COGNITIVE_DIR/session.json" ]]; then
      echo ""
      echo "Note: $COGNITIVE_DIR/session.json not found."
      echo "Run the DB Block pipeline first (mention a .jsonl file in your prompt) to generate a profile."
    fi
    ;;
  *)
    echo "Usage: toggle.sh [stop|start]" >&2
    exit 1
    ;;
esac
