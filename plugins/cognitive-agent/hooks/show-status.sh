#!/bin/bash
set -euo pipefail

HOOK_INPUT=$(cat)
COGNITIVE_DIR="$CLAUDE_PROJECT_DIR/.cognitive"
SESSION_INDEX="$COGNITIVE_DIR/session.index.md"
DISABLED_FLAG="$COGNITIVE_DIR/.disabled"

# Check session-scoped disabled flag
if [[ -f "$DISABLED_FLAG" ]]; then
  CURRENT_SESSION=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""')
  DISABLED_SESSION=$(cat "$DISABLED_FLAG")
  if [[ "$CURRENT_SESSION" == "$DISABLED_SESSION" ]]; then
    exit 0
  fi
  # Stale flag — clean it up
  rm -f "$DISABLED_FLAG"
fi

if [[ ! -f "$SESSION_INDEX" ]]; then
  exit 0
fi

EXCERPT_COUNT=$(wc -l < "$SESSION_INDEX" | tr -d ' ')
echo "💡 Cognitive Agent active — ${EXCERPT_COUNT} excerpt(s) in profile"
