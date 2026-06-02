#!/bin/bash
set -euo pipefail

HOOK_INPUT=$(cat)
COGNITIVE_DIR="$CLAUDE_PROJECT_DIR/.cognitive"
SESSION_JSON="$COGNITIVE_DIR/session.json"
SESSION_INDEX="$COGNITIVE_DIR/session.index.md"
DISABLED_FLAG="$COGNITIVE_DIR/.disabled"

# Check session-scoped disabled flag
if [[ -f "$DISABLED_FLAG" ]]; then
  CURRENT_SESSION=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""')
  DISABLED_SESSION=$(cat "$DISABLED_FLAG")
  if [[ "$CURRENT_SESSION" == "$DISABLED_SESSION" ]]; then
    echo '{"decision": "approve"}'
    exit 0
  fi
  # Stale flag from a previous session — clean it up
  rm -f "$DISABLED_FLAG"
fi

# Silent no-op when profile files are absent
if [[ ! -f "$SESSION_JSON" || ! -f "$SESSION_INDEX" ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Sliding Triad: last 3 user/assistant turns from transcript
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // ""')
SLIDING_TRIAD=""
if [[ -f "$TRANSCRIPT_PATH" ]]; then
  SLIDING_TRIAD=$(
    grep '"role":"user"\|"role":"assistant"' "$TRANSCRIPT_PATH" \
    | tail -n 6 \
    | jq -rs '
        map(
          (.message.role // "?") + ": " +
          ((.message.content[]? | select(.type == "text") | .text) // "" | .[0:300])
        ) | join("\n---\n")
      ' 2>/dev/null || echo "(transcript unreadable)"
  )
fi

INDEX=$(cat "$SESSION_INDEX")

MSG="💡 Cognitive Agent active.

## Recent turns (Sliding Triad)
${SLIDING_TRIAD}

## Cognitive Index (excerpt_id | category | subcategory | user_text snippet)
${INDEX}

## Full records
Available at: ${SESSION_JSON}
Read specific excerpt_ids from that file if relevant to the current topic."

jq -n --arg msg "$MSG" '{"decision": "approve", "systemMessage": $msg}'
