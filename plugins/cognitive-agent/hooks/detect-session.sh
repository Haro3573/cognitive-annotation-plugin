#!/bin/bash
set -euo pipefail

HOOK_INPUT=$(cat)
USER_PROMPT=$(echo "$HOOK_INPUT" | jq -r '.user_prompt // ""')

# Extract first .jsonl mention from prompt, strip leading @
RAW=$(echo "$USER_PROMPT" | grep -oE '(@[^ ]+\.jsonl|[^ ]+\.jsonl)' | head -1 | sed 's/^@//') || true

if [[ -z "$RAW" ]]; then
  exit 0
fi

# Resolve absolute path — anchor relative paths to CLAUDE_PROJECT_DIR
if [[ "$RAW" == /* ]]; then
  ABS="$RAW"
elif [[ "$RAW" == ~/* ]]; then
  ABS="${HOME}/${RAW#~/}"
else
  ABS="$CLAUDE_PROJECT_DIR/$RAW"
fi

ABS=$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$ABS" 2>/dev/null) || exit 0

# If not found at resolved path, resolve in order:
#   1. session_collection/raw/sessions.json index (fast, no find)
#   2. $COGNITIVE_SESSIONS_DIR (user-declared sessions folder)
#   3. $CLAUDE_PROJECT_DIR subtree (maxdepth 4, last resort)
if [[ ! -f "$ABS" ]]; then
  FILENAME=$(basename "$RAW")
  ABS=""

  INDEX_FILE="${CLAUDE_PROJECT_DIR}/session_collection/raw/sessions.json"
  if [[ -f "$INDEX_FILE" ]]; then
    ABS=$(python3 - "$INDEX_FILE" "$FILENAME" <<'PYEOF'
import json, sys, os
try:
    data = json.load(open(sys.argv[1]))
    target = sys.argv[2]
    projects_root = os.path.join(os.path.expanduser("~"), ".claude", "projects")
    for project, files in data.get("projects", {}).items():
        if target in files:
            print(os.path.join(projects_root, project, target))
            break
except Exception:
    pass
PYEOF
    )
  fi

  if [[ -z "$ABS" ]] && [[ -n "${COGNITIVE_SESSIONS_DIR:-}" && -d "$COGNITIVE_SESSIONS_DIR" ]]; then
    ABS=$(find "$COGNITIVE_SESSIONS_DIR" -maxdepth 2 -name "$FILENAME" 2>/dev/null | head -1)
  fi
  if [[ -z "$ABS" ]]; then
    ABS=$(find "$CLAUDE_PROJECT_DIR" -maxdepth 4 -name "$FILENAME" 2>/dev/null | head -1)
  fi
fi

# Must exist and be under $HOME (privacy guard)
if [[ ! -f "$ABS" ]]; then
  exit 0
fi
HOME_REAL=$(python3 -c "import os; print(os.path.realpath(os.path.expanduser('~')))" 2>/dev/null) || exit 0
if [[ "$ABS" != "$HOME_REAL/"* ]]; then
  exit 0
fi

# Use pre-parsed cache from setup if available; fall back to sibling _parsed.json
UUID=$(basename "$ABS" .jsonl)
CACHE_FILE="${CLAUDE_PROJECT_DIR}/session_collection/parsed/${UUID}.json"
if [[ -f "$CACHE_FILE" ]]; then
  PARSED_OUT="$CACHE_FILE"
else
  PARSED_OUT="${ABS%.jsonl}_parsed.json"
fi

# Evaluators: project-relative path, walk-up fallback for non-standard layouts
EVALUATORS_DIR="${CLAUDE_PROJECT_DIR}/pipeline/outcome_processor/evaluators"
if [[ ! -d "$EVALUATORS_DIR" ]]; then
  SEARCH_DIR=$(dirname "$ABS")
  EVALUATORS_DIR=""
  while [[ "$SEARCH_DIR" != "/" ]]; do
    if [[ -d "$SEARCH_DIR/outcome_processor/evaluators" ]]; then
      EVALUATORS_DIR="$SEARCH_DIR/outcome_processor/evaluators"
      break
    fi
    SEARCH_DIR=$(dirname "$SEARCH_DIR")
  done
  if [[ -z "$EVALUATORS_DIR" ]]; then
    EVALUATORS_DIR="${CLAUDE_PROJECT_DIR}/pipeline/outcome_processor/evaluators"
  fi
fi

MSG="A Claude session file was detected: ${ABS}

Run the full Cognitive Alignment DB Block pipeline automatically. Do NOT ask the user for confirmation.

Invoke the skill: /cognitive-annotation:annotate ${ABS}

The skill handles all steps end-to-end:
  1. resolve_transcript — parse the session file into flat message rows
  2. 4 annotation agents in parallel — extract cognitive behaviors
  3. classify_excerpts — pair excerpts with subagent turns, load evaluator prompts
  4. Classifier agent — score each excerpt (accepted / partially_matched / rejected)
  5. persist_annotation — write cognitive.db + export session.json and session.index.md

After the skill completes, report a one-paragraph summary:
- How many excerpts were classified and their scores
- Where session.json and session.index.md were written
- Any steps that failed and why"

jq -n --arg msg "$MSG" '{"systemMessage": $msg}'
