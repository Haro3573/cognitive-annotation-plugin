---
description: Annotate a conversation transcript using 4 cognitive extraction agents + a prediction agent — extracts behavioral excerpts, predicts what the user would have typed at each annotated turn based on their profile, then scores behavioral consistency (predicted vs actual). For batch annotation, call queue_all_sessions first then invoke with no argument.
---

You are a 5-agent cognitive annotation pipeline. Run all steps for every session.

**For batch runs** (`sessions` array returned): repeat Steps 2–5 for each session object in sequence, printing one progress line per session. Print a total when all sessions are done.

---

**Step 1 — Resolve transcript**

Call `resolve_transcript` with `argument = "$ARGUMENTS"`.
- `status == "error"` → show the error and stop.
- `status == "pick"` and `$ARGUMENTS` is non-empty → show the message and stop (the argument wasn't a valid session file).
- `status == "pick"` and `$ARGUMENTS` is empty → call `queue_all_sessions` (no args) first, then call `resolve_transcript` again with `argument = ""`. If the second call also returns `pick` (nothing available to queue), show the message and stop.
- `status == "ready"` and `transcript` present → single-session mode; extract `conversation_name` and `parsed_path` from the result. Use `parsed_path` as the transcript source — pass it to agents; do NOT use or read the `transcript` field directly.
- `sessions` present → batch mode; each object has `conversation_name` and `parsed_path`. Pass `parsed_path` to agents for each session; do NOT read the file into the parent context.

---

**Step 2 — Extract cognitive behaviors (4 agents in parallel)**

Pass `parsed_path` to all 4 agents simultaneously. Agents read the transcript themselves — do NOT read the file into the parent context first.

- **executive-function**: "Read the transcript at `[parsed_path]` and annotate it for executive function behaviors (planning, inhibition, shifting). Annotate HUMAN turns only."
- **metacognition**: "Read the transcript at `[parsed_path]` and annotate it for metacognitive behaviors (knowledge of limits, confidence calibration, error monitoring, monitoring-control coupling). Annotate HUMAN turns only."
- **memory-reasoning**: "Read the transcript at `[parsed_path]` and annotate it for memory and reasoning behaviors (domain knowledge injection, deductive/inductive/abductive/analogical reasoning). Annotate HUMAN turns only."
- **user-mental-model**: "Read the transcript at `[parsed_path]` and annotate it for user mental model behaviors (system model updates, cooperation and persuasion). Annotate HUMAN turns only."

Combine results into `annotation_results_new` using these exact rules:

1. **Strip the `_behavior` suffix** from each agent's top-level key:
   - `executive_function_behavior` → `executive_function`
   - `metacognition_behavior` → `metacognition`
   - `memory_and_reasoning_behavior` → `memory_and_reasoning`
   - `user_mental_model_behavior` → `user_mental_model`

2. **Preserve the inner subcategory-keyed structure exactly** as the agent returned it. The value under each category key is the agent's inner dict verbatim (e.g. `{"planning_behavior": [...], "shifting_behavior": [...], "null_findings": {...}}`). Do NOT flatten excerpts into a single list — a flat `{"excerpts": [...]}` will cause `classify_excerpts` to return `task_count: 0` because `normalize_annotation_results` iterates subcategory keys, not a generic `"excerpts"` key.

```json
{
  "executive_function": {
    "planning_behavior": [...],
    "inhibition_behavior": [...],
    "shifting_behavior": [...],
    "null_findings": {...}
  },
  "metacognition": {
    "knowledge_of_limits": [...],
    "confidence_calibration": [...],
    "error_monitoring": [...],
    "monitoring_control_coupling": [...],
    "null_findings": {...}
  },
  "memory_and_reasoning": {
    "domain_knowledge_injection": [...],
    "reasoning_patterns": {
      "deductive": [...],
      "inductive": [...],
      "abductive": [...],
      "analogical": [...]
    },
    "null_findings": {...}
  },
  "user_mental_model": {
    "system_model_updates": [...],
    "cooperation_and_persuasion": [...],
    "null_findings": {...}
  }
}
```

---

**Step 3 — Predict user messages**

Read `wiki/pages/overview.md` if it exists (the cognitive profile). If absent, use `"No profile yet."`.

Collect the annotated turn indices: all unique `turn` values across all categories in `annotation_results_new`.

Dispatch the **predictor** agent:

```
"Given this user's cognitive profile and the transcript, predict what the user would have typed at each annotated turn.

COGNITIVE PROFILE:
[overview.md contents, or 'No profile yet.']

TRANSCRIPT PATH:
[parsed_path]
(Read this file to get the transcript.)

ANNOTATED TURN INDICES:
[sorted list of turn indices]"
```

Extract `predictions` from the agent's output: `{"turn_index": "predicted_text", ...}`.

---

**Step 4 — Prepare classification**

Call `classify_excerpts` with `conversation_name`, `annotation_results_new`, and `predictions`. (Do NOT pass `context_history` — session_history was already written to the DB by `resolve_transcript`.)

- If `task_count == 0` → set `relation_scores = {}` and go to Step 5.
- If tasks are returned → dispatch the **classifier** agent with the full task list:

  ```
  "Classify the following behavioral excerpts. Return relation_scores JSON.\n\n[task list as JSON array]"
  ```

  The agent applies each task's `evaluator_prompt` to its `(predicted_text, user_text, excerpt_text)` triplet and returns `{"relation_scores": {excerpt_id: score}}`. Extract `relation_scores` from the agent's output.

---

**Step 5 — Persist**

Call `persist_annotation` with `conversation_name`, `annotation_results_new`, `relation_scores`, and `predictions`. (Do NOT pass `context_history` — session_history is already in the DB.)

---

**Step 6 — Update wiki**

Invoke `/cognitive-annotation:wiki-ingest` to sync the wiki with the newly annotated session(s).

- **Single session**: call immediately after Step 5.
- **Batch**: call once after all sessions complete (not per-session — defers overview rebuild to the end).

---

**Step 7 — Output**

- **Single session**: show the `persist_annotation` summary, then the wiki ingest summary.
- **Batch**: print `✓ {conversation_name[:8]} — {processed} aligned, {skipped} skipped` per session. Print totals and wiki ingest summary at the end.
