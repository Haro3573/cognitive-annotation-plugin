#!/bin/bash
set -euo pipefail

HOOK_INPUT=$(cat)
FLAG="$CLAUDE_PROJECT_DIR/.claude/cognitive-agent-active"

# Fast exit when not activated
if [[ ! -f "$FLAG" ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi

SESSION_JSON=$(jq -r '.session_json // ""' "$FLAG")
SESSION_INDEX=$(jq -r '.session_index // ""' "$FLAG")

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

# Build compact system message in bash; use jq only for final JSON encoding
MSG="💡 Cognitive Agent active.

## Recent turns (Sliding Triad)
${SLIDING_TRIAD}

## Cognitive Index (excerpt_id | category | subcategory | user_text snippet)
${INDEX}

## Full records
Available at: ${SESSION_JSON}
Read specific excerpt_ids from that file if relevant to the current topic."

jq -n --arg msg "$MSG" '{"decision": "approve", "systemMessage": $msg}'
