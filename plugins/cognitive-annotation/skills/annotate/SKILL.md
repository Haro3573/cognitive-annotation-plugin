---
description: Annotate a conversation transcript using 4 cognitive extraction agents — extracts behavioral excerpts, retrieves the most similar past excerpt per subcategory from cognitive.db, then scores cross-session behavioral consistency (current vs past). For batch annotation, call queue_all_sessions first then invoke with no argument.
---

You are a 5-agent cognitive annotation pipeline. Run all steps for every session.

**For batch runs** (`sessions` array returned): repeat Steps 1 (resolve per session) through 5 for each session object in sequence, printing one progress line per session. Print totals when all sessions are done.

---

**Step 1 — Resolve transcript**

Call `resolve_transcript` with `argument = "$ARGUMENTS"`.
- `status == "error"` → show the error and stop.
- `status == "pick"` and `$ARGUMENTS` is non-empty → show the message and stop (the argument wasn't a valid session file).
- `status == "pick"` and `$ARGUMENTS` is empty → call `queue_all_sessions` (no args) first, then call `resolve_transcript` again with `argument = ""`. If the second call also returns `pick` (nothing available to queue), show the message and stop.
- `status == "ready"` and no `window_paths` → single-session mode (small session); extract `conversation_name` and `parsed_path`.
- `status == "ready"` and `window_paths` present → single-session mode (large session); extract `conversation_name`, `parsed_path`, and `window_paths`. Process each window sequentially through Step 2 (windowed path).
- `sessions` present → batch mode; each object has `conversation_name` and `parsed_path`. For each session, call `resolve_transcript` with `argument = parsed_path`:
  - If `status == "error"` or `status == "pick"` → log the failure (capture the error message from the result and conversation_name) and skip this session (count as failed); continue with the next.
  - If `status == "ready"` and no `window_paths` → small session; if `status == "ready"` and `window_paths` present → large session. Extract `conversation_name`, `parsed_path`, and `window_paths` (if present) from the result. Then process through Steps 2–5.

---

**Step 2 — Extract cognitive behaviors (4 agents in parallel)**

Choose a temp file prefix for this annotation run — use flat files directly in `$TMPDIR`, no subdirectory:
```
{prefix} = $TMPDIR/cog_{conversation_name[:8]}
```
Expand `$TMPDIR` to its actual value (e.g. run `echo $TMPDIR` via Bash if needed).

**Small session** (no `window_paths`): dispatch all 4 agents simultaneously — replace `{parsed_path}` and `{prefix}` with actual values:

- **executive-function**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {parsed_path}\n\nOutput path: {prefix}_executive_function.json"`
- **metacognition**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {parsed_path}\n\nOutput path: {prefix}_metacognition.json"`
- **memory-reasoning**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {parsed_path}\n\nOutput path: {prefix}_memory_reasoning.json"`
- **user-mental-model**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {parsed_path}\n\nOutput path: {prefix}_user_mental_model.json"`

After all 4 agents complete, read the 4 output files. Build `annotation_results_new` from their contents (apply key-stripping rules below).

**Large session** (`window_paths` present): for each window N (0-indexed) in `window_paths` sequentially, dispatch all 4 agents in parallel:

- **executive-function**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {window_paths[N]}\n\nOutput path: {prefix}_executive_function_w{N}.json"`
- **metacognition**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {window_paths[N]}\n\nOutput path: {prefix}_metacognition_w{N}.json"`
- **memory-reasoning**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {window_paths[N]}\n\nOutput path: {prefix}_memory_reasoning_w{N}.json"`
- **user-mental-model**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {window_paths[N]}\n\nOutput path: {prefix}_user_mental_model_w{N}.json"`

After all windows complete, read all per-window files. Merge per category by concatenating each subcategory list across windows (e.g., all `planning_behavior` items from w0 + w1 + ...). Include `null_findings` only from windows where all other subcategories in that category were empty. Build `annotation_results_new` from merged results.

Apply these rules when building `annotation_results_new` from file contents:

1. **Strip the `_behavior` suffix** from each file's top-level key:
   - `executive_function_behavior` → `executive_function`
   - `metacognition_behavior` → `metacognition`
   - `memory_and_reasoning_behavior` → `memory_and_reasoning`
   - `user_mental_model_behavior` → `user_mental_model`

2. **Preserve the inner subcategory-keyed structure exactly** as the agent wrote it. The value under each category key is the agent's inner dict verbatim (e.g. `{"planning_behavior": [...], "shifting_behavior": [...], "null_findings": {...}}`). Do NOT flatten excerpts into a single list — a flat `{"excerpts": [...]}` will cause `classify_excerpts` to return `task_count: 0` because `normalize_annotation_results` iterates subcategory keys, not a generic `"excerpts"` key.

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

**Step 3 — Prepare classification**

Call `classify_excerpts` with `conversation_name` and `annotation_results_new`. (Do NOT pass `context_history` — session_history was already written to the DB by `resolve_transcript`.)

The tool queries cognitive.db for past excerpts in the same subcategory from other sessions, and returns a task list where each task has a `past_candidates` array.

- If `task_count == 0` → set `relation_scores = {}`, `matched_past = {}`, and go to Step 4.
- If tasks are returned → dispatch the **classifier** agent with the full task list:

  ```
  "Classify the following behavioral excerpts for cross-session behavioral consistency.

  The response includes an `evaluators` dict keyed by category — use evaluators[task.category] as the scoring rubric for each task.

  For each task:
  - If past_candidates is empty: skip it entirely — do NOT include it in your response.
  - Otherwise: read the current excerpt (excerpt_text, user_text) and all past_candidates. Pick the most semantically similar past candidate by index number. Apply evaluators[task.category] to score behavioral consistency between the current excerpt and the selected past candidate.

  Return ONLY:
  {
    \"relation_scores\": {\"excerpt_id\": \"accepted|partially_matched|rejected\"},
    \"matched_indices\": {\"excerpt_id\": 0}
  }
  Only include excerpts that had past_candidates. Do not include tasks with empty past_candidates.

  [full classify_excerpts response as JSON]"
  ```

  Extract `relation_scores` and `matched_indices` from the agent's output.

  Resolve `matched_indices` to `matched_past` (IDs) using the task list you already have:
  ```
  matched_past = {}
  for excerpt_id, candidate_index in matched_indices.items():
      task = find task where task["excerpt_id"] == excerpt_id
      matched_past[excerpt_id] = task["past_candidates"][candidate_index]["excerpt_id"]
  ```

---

**Step 4 — Persist**

Call `persist_annotation` with `conversation_name`, `annotation_results_new`, `relation_scores`, and `matched_past`. (Do NOT pass `context_history` — session_history is already in the DB.)

---

**Step 5 — Update wiki**

Invoke `/cognitive-annotation:wiki-ingest` to sync the wiki with the newly annotated session(s).

- **Single session**: call immediately after Step 4.
- **Batch**: call once after all sessions complete (not per-session — defers overview rebuild to the end).

---

**Step 6 — Output**

- **Single session**: show the `persist_annotation` summary, then the wiki ingest summary.
- **Batch**: for each session:
  - If the session was failed (resolve_transcript error) → print `✗ {conversation_name[:8]} — failed ({error_message})`
  - Otherwise → print `✓ {conversation_name[:8]} — {processed} aligned, {skipped} skipped`
  - Print totals (sessions processed, sessions failed, excerpts aligned, excerpts skipped) and wiki ingest summary at the end.
