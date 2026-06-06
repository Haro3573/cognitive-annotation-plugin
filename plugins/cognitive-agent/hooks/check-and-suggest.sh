#!/bin/bash
set -euo pipefail

HOOK_INPUT=$(cat)

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

if [[ ! -f "$ACTIVE_FLAG" ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# MARKER TEST — determines which Stop hook output channel is user-visible vs Claude-visible.
# After testing, replace this block with the real insight logic.
#
# Instructions for the user:
#   1. bash setup.sh && restart Claude Code
#   2. /cognitive-agent:start
#   3. Send any prompt and wait for Claude's response
#   4. In your NEXT message ask: "Do you see MARKER_REASON or MARKER_SYSM anywhere?"
#      - Whichever Claude says it sees → that field reaches the LLM context (avoid it)
#      - Whichever is visible in the transcript sidebar but Claude denies → that's our channel
jq -n '{
  "decision": "approve",
  "reason": "MARKER_REASON — visible here in reason field",
  "systemMessage": "MARKER_SYSM — visible here in systemMessage field"
}'
