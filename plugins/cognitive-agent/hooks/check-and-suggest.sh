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

PROJECT_ROOT="$(_find_project_root)"
COGNITIVE_DIR="$PROJECT_ROOT/.cognitive"
ACTIVE_FLAG="$COGNITIVE_DIR/.active"

if [[ ! -f "$ACTIVE_FLAG" ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Prevent recursive hook calls from claude -p subprocess sessions
LOCK_FILE="$COGNITIVE_DIR/.suggesting"
if [[ -f "$LOCK_FILE" ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

SESSION_INDEX="$COGNITIVE_DIR/session.index.md"
OVERVIEW="$PROJECT_ROOT/wiki/pages/overview.md"
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // ""')

if [[ ! -f "$SESSION_INDEX" && ! -f "$OVERVIEW" ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi

if [[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Extract last 3 user/assistant turns as sliding triad
TRIAD=$(python3 - "$TRANSCRIPT_PATH" <<'PYEOF'
import sys, json

turns = []
try:
    with open(sys.argv[1]) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            role = obj.get('type', '')
            if role not in ('user', 'assistant'):
                continue
            msg = obj.get('message', {})
            if isinstance(msg, dict):
                content = msg.get('content', '')
                if isinstance(content, list):
                    text = ' '.join(
                        b.get('text', '') for b in content
                        if isinstance(b, dict) and b.get('type') == 'text'
                    )
                else:
                    text = str(content)
            else:
                text = str(msg)
            text = text.strip()
            if text and not text.startswith('<'):
                turns.append(f"{role.upper()}: {text[:400]}")
except Exception:
    pass

print('\n\n'.join(turns[-3:]))
PYEOF
)

# Profile: wiki overview (synthesized, primary) or session.index.md (raw fallback)
if [[ -f "$OVERVIEW" ]]; then
  PROFILE=$(cat "$OVERVIEW")
else
  PROFILE=$(head -20 "$SESSION_INDEX" 2>/dev/null || true)
fi

if [[ -z "$PROFILE" ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Locate claude binary — ~/.local/bin is common install path, may not be in hook PATH
CLAUDE_BIN=$(command -v claude 2>/dev/null || echo "$HOME/.local/bin/claude")

if [[ ! -x "$CLAUDE_BIN" ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Load agent prompt from the plugin — falls back to a minimal inline prompt if missing
AGENT_PROMPT_FILE="${CLAUDE_PLUGIN_ROOT}/hooks/agent-prompt.md"
if [[ -f "$AGENT_PROMPT_FILE" ]]; then
  AGENT_PROMPT=$(cat "$AGENT_PROMPT_FILE")
else
  AGENT_PROMPT="You are a cognitive insight generator. Write ONE insight (1-2 sentences) grounded in the profile. Start with 💡. No preamble."
fi

# Generate insight via a fresh claude -p instance (isolated — main session untouched)
INSIGHT=$("$CLAUDE_BIN" -p "${AGENT_PROMPT}

BEHAVIORAL PROFILE:
${PROFILE}

RECENT TURNS:
${TRIAD}" 2>/dev/null | head -3 || true)

if [[ -z "$INSIGHT" ]]; then
  echo '{"decision": "approve"}'
  exit 0
fi

# Write sidecar record alongside the session JSONL for the annotation pipeline
UUID=$(basename "$TRANSCRIPT_PATH" .jsonl)
SIDECAR="$(dirname "$TRANSCRIPT_PATH")/${UUID}_cognitive.jsonl"

TURN_INDEX=$(python3 -c "
import json
n = 0
with open('$TRANSCRIPT_PATH') as f:
    for line in f:
        if line.strip():
            try:
                if json.loads(line).get('type') in ('user', 'assistant'):
                    n += 1
            except Exception:
                pass
print(n)
" 2>/dev/null || echo "0")

LAST_ASSISTANT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null || true)

python3 -c "
import json, sys
print(json.dumps({
    'session_id': '$UUID',
    'turn_index': int('$TURN_INDEX'),
    'advice_text': sys.argv[1],
    'last_assistant_content': sys.argv[2],
    'timestamp': '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
}))
" "$INSIGHT" "$LAST_ASSISTANT" >> "$SIDECAR" 2>/dev/null || true

# Display via systemMessage — display-only, Claude does not see this
jq -n --arg msg "$INSIGHT" '{"decision": "approve", "systemMessage": $msg}'
