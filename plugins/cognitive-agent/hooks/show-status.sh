#!/bin/bash
set -euo pipefail

COGNITIVE_DIR="$CLAUDE_PROJECT_DIR/.cognitive"
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
