#!/bin/bash
set -euo pipefail

SESSION_JSON="${1:-}"
SESSION_INDEX="${2:-}"

if [[ -z "$SESSION_JSON" || -z "$SESSION_INDEX" ]]; then
  echo "❌ Usage: /cognitive-agent:start <path/to/session.json> <path/to/session.index.md>" >&2
  echo "" >&2
  echo "   Example:" >&2
  echo "     /cognitive-agent:start /path/to/session.json /path/to/session.index.md" >&2
  exit 1
fi

# Resolve to absolute paths
SESSION_JSON="$(cd "$(dirname "$SESSION_JSON")" && pwd)/$(basename "$SESSION_JSON")"
SESSION_INDEX="$(cd "$(dirname "$SESSION_INDEX")" && pwd)/$(basename "$SESSION_INDEX")"

if [[ ! -f "$SESSION_JSON" ]]; then
  echo "❌ session.json not found: $SESSION_JSON" >&2
  echo "" >&2
  echo "   Generate it first by calling the MCP tool:" >&2
  echo "     export_session_snapshot(conversation_name=\"<your-conv-id>\")" >&2
  echo "   This writes session.json and session.index.md to your project directory." >&2
  exit 1
fi

if [[ ! -f "$SESSION_INDEX" ]]; then
  echo "❌ session.index.md not found: $SESSION_INDEX" >&2
  echo "" >&2
  echo "   Generate it first by calling the MCP tool:" >&2
  echo "     export_session_snapshot(conversation_name=\"<your-conv-id>\")" >&2
  exit 1
fi

mkdir -p .claude

cat > .claude/cognitive-agent-active <<EOF
{
  "session_json": "$SESSION_JSON",
  "session_index": "$SESSION_INDEX",
  "session_id": "${CLAUDE_CODE_SESSION_ID:-}",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "✓ Cognitive agent activated"
echo "  session.json:     $SESSION_JSON"
echo "  session.index.md: $SESSION_INDEX"
echo ""
echo "  A 💡 cognitive insight will appear after each AI response."
echo "  To deactivate: /cognitive-agent:stop"
