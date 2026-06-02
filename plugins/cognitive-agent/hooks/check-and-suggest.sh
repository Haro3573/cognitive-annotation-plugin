#!/bin/bash
set -euo pipefail

HOOK_INPUT=$(cat)
COGNITIVE_DIR="$CLAUDE_PROJECT_DIR/.cognitive"
SESSION_JSON="$COGNITIVE_DIR/session.json"
SESSION_INDEX="$COGNITIVE_DIR/session.index.md"
ACTIVE_FLAG="$COGNITIVE_DIR/.active"
SUGGESTING_FLAG="$COGNITIVE_DIR/.suggesting"

# Only fire when explicitly activated by /cognitive-agent:start
if [[ ! -f "$ACTIVE_FLAG" ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Silent no-op when profile files are absent
if [[ ! -f "$SESSION_JSON" || ! -f "$SESSION_INDEX" ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Loop control: if we blocked on the previous Stop to request an insight, now approve
if [[ -f "$SUGGESTING_FLAG" ]]; then
  CURRENT_TIME=$(date +%s)
  FLAG_TIME=$(cat "$SUGGESTING_FLAG" 2>/dev/null || echo 0)
  if (( CURRENT_TIME - FLAG_TIME < 300 )); then
    rm -f "$SUGGESTING_FLAG"
    echo '{"decision": "approve"}'
    exit 0
  fi
  # Stale flag (crash between block and approve) — remove and fall through
  rm -f "$SUGGESTING_FLAG"
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

# Write timestamp for loop control
date +%s > "$SUGGESTING_FLAG"

MSG="Output a cognitive insight for the user. Rules:
- Start with exactly '💡' on the first line
- 1-3 sentences only
- Reference a specific pattern from the profile below — be concrete, not generic
- No preamble, no follow-up questions, nothing else

## Cognitive Profile (excerpt_id | category | subcategory | behavior)
${INDEX}

## Recent Conversation
${SLIDING_TRIAD}"

jq -n --arg msg "$MSG" '{"decision": "block", "systemMessage": $msg}'
