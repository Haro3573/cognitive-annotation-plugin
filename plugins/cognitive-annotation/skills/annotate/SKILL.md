---
description: Annotate a conversation transcript using 4 cognitive extraction agents — extracts behavioral excerpts, then uses embedding similarity to match each excerpt to the most similar past excerpt in the same subcategory across sessions. For batch annotation, call queue_all_sessions first then invoke with no argument.
---

You are a 4-agent cognitive annotation pipeline. Run all steps for every session.

**For batch runs** (`sessions` array returned): repeat Steps 1 (resolve per session) through 4 for each session object in sequence, printing one progress line per session. Print totals when all sessions are done.

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
  - If `status == "ready"` and no `window_paths` → small session; if `status == "ready"` and `window_paths` present → large session. Extract `conversation_name`, `parsed_path`, and `window_paths` (if present) from the result. Then process through Steps 2–4.

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

2. **Preserve the inner subcategory-keyed structure exactly** as the agent wrote it. The value under each category key is the agent's inner dict verbatim (e.g. `{"planning_behavior": [...], "shifting_behavior": [...], "null_findings": {...}}`). Do NOT flatten excerpts into a single list — a flat `{"excerpts": [...]}` will be silently ignored by `normalize_annotation_results`, which iterates subcategory keys, not a generic `"excerpts"` key.

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

**Step 3 — Persist**

Call `persist_annotation` with `conversation_name` and `annotation_results_new`.

The tool writes all excerpts to cognitive.db, runs embedding-based sync to find the best
cross-session match per excerpt, updates `subagent_comment` and similarity scores, and
exports the session snapshot. No `relation_scores` or `matched_past` needed.

---

**Step 4 — Update wiki**

Invoke `/cognitive-annotation:wiki-ingest` to sync the wiki with the newly annotated session(s).

- **Single session**: call immediately after Step 3.
- **Batch**: call once after all sessions complete (not per-session — defers overview rebuild to the end).

---

**Step 5 — Output**

- **Single session**: show the `persist_annotation` summary, then the wiki ingest summary.
- **Batch**: for each session:
  - If the session was failed (resolve_transcript error) → print `✗ {conversation_name[:8]} — failed ({error_message})`
  - Otherwise → print `✓ {conversation_name[:8]} — {processed} aligned, {skipped} skipped`
  - Print totals (sessions processed, sessions failed, excerpts aligned, excerpts skipped) and wiki ingest summary at the end.
