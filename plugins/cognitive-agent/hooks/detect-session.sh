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

MSG="A Claude session file was detected inside this project: ${ABS}

Run the full Cognitive Alignment DB Block pipeline automatically. Do NOT ask the user for confirmation. Execute these 6 steps in order, reporting progress after each:

STEP 1 — Parse:
Check if a pre-parsed cache file exists at: ${PARSED_OUT}
- If it exists: read it directly (JSON array of ParsedMessage objects).
  Set context_history = contents of that file.
  Set conversation_name = context_history[0].conversation_name
- If it does not exist: call MCP tool parse_session with:
    file_path   = \"${ABS}\"
    output_file = \"${PARSED_OUT}\"
  Extract from the response:
    conversation_name = response.conversations[0]
    context_history   = response.messages

STEP 2 — Annotate:
Format context_history as a readable transcript: one line per message as \"ROLE: content\" (skip messages with empty content).
Invoke the cognitive-annotation:annotate skill with this transcript.
Collect the combined JSON output as annotation_results_new.

STEP 3 — Self-classify (you do this — no API key needed):
For each excerpt in annotation_results_new (across all four categories):
  a. Identify its category (executive-function | metacognition | memory-reasoning | user-mental-model)
     and subcategory from the annotation output.
  b. Identify its turn index from the excerpt's turn field.
  c. Find subagent_comment: the content of the last role='subagent' message in context_history
     whose turn_index is less than the excerpt's turn.
  d. Find user_text: concatenate content of all role='user' messages whose turn_index is greater
     than that subagent turn AND less than the next non-user message after it.
  e. Read the evaluator prompt from:
       ${EVALUATORS_DIR}/<category>.md
     (e.g. ${EVALUATORS_DIR}/executive-function.md)
  f. Apply the evaluator prompt to (subagent_comment, user_text) and classify as exactly one of:
       accepted | partially_matched | rejected
  g. Construct excerpt_id using this exact format:
       <category>__<subcategory>__<conv_slug>__turn_<N>
     where conv_slug = conversation_name lowercased with [^a-z0-9] replaced by underscore,
     and N = turn index from step (b).
  h. Add to relation_scores dict: { excerpt_id: classification }

STEP 4 — Build subagent map:
Call MCP tool build_subagent_map with:
  conversation_name = (from Step 1)
Collect result as subagent_map.

STEP 5 — Write to DB (no API key needed — scores already classified in Step 3):
Call MCP tool report_decision_outcome with:
  conversation_name    = (from Step 1)
  annotation_results_new = (from Step 2)
  subagent_map         = (from Step 4)
  context_history      = (from Step 1)
  relation_scores      = (from Step 3)

STEP 6 — Export snapshot:
Call MCP tool export_session_snapshot with:
  conversation_name = (from Step 1)

After all steps complete, report a one-paragraph summary:
- How many excerpts were classified and their scores
- Where session.json and session.index.md were written
- Any steps that failed and why"

jq -n --arg msg "$MSG" '{"systemMessage": $msg}'
