#!/bin/bash
set -euo pipefail

FLAG="$CLAUDE_PROJECT_DIR/.claude/cognitive-agent-active"

if [[ ! -f "$FLAG" ]]; then
  exit 0
fi

SESSION_INDEX=$(jq -r '.session_index // ""' "$FLAG")

if [[ ! -f "$SESSION_INDEX" ]]; then
  exit 0
fi

EXCERPT_COUNT=$(wc -l < "$SESSION_INDEX" | tr -d ' ')
echo "💡 Cognitive Agent active — ${EXCERPT_COUNT} excerpt(s) in profile"
