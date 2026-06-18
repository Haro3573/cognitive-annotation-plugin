---
description: Annotate a conversation transcript using 4 cognitive extraction agents — extracts behavioral excerpts, then uses embedding similarity to match each excerpt to the most similar past excerpt in the same subcategory across sessions. For batch annotation, call queue_all_sessions first then invoke with no argument.
---

You are a 4-agent cognitive annotation pipeline. Run all steps for every session.

**For batch runs** (`sessions` array returned): repeat Steps 1 (resolve per session) through 4 for each session object in sequence, printing one progress line per session. Print totals when all sessions are done.

---

**Step 1 — Resolve transcript**

> **Token note:** Pass a file *path* as the argument (e.g. `/path/to/session.jsonl`), not an @mention. @mention expansion inlines the full raw JSONL into context before this tool call — 10–100× larger than the stripped view the server writes to disk. If `$ARGUMENTS` looks like expanded NDJSON content rather than a path, warn the user and stop; ask them to pass the file path directly or use the queue system.

Call `resolve_transcript` with `argument = "$ARGUMENTS"`.
- `status == "error"` → show the error and stop.
- `status == "pick"` and `$ARGUMENTS` is non-empty → show the message and stop (the argument wasn't a valid session file).
- `status == "pick"` and `$ARGUMENTS` is empty → call `queue_all_sessions` (no args) first, then call `resolve_transcript` again with `argument = ""`. If the second call also returns `pick` (nothing available to queue), show the message and stop.
- `status == "ready"` and no `window_paths` → single-session mode (small session); extract `conversation_name` and `parsed_path`.
- `status == "ready"` and `window_paths` present → single-session mode (large session); extract `conversation_name`, `parsed_path`, and `window_paths`. Process each window sequentially through Step 2 (windowed path).
- `sessions` present → batch mode; each object has `conversation_name`, `parsed_path`, and `user_turn_count`. For each session:
  - If `user_turn_count` ≤ 50: small session — skip the per-session `resolve_transcript` call (the parsed_path is already returned in the batch result). Process through Steps 2–4 with no `window_paths`.
  - If `user_turn_count` > 50: large session — call `resolve_transcript` with `argument = parsed_path` to get `window_paths`. If `status == "error"` or `status == "pick"` → log the failure and skip.

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

After all 4 agents complete, note the `{prefix}` value — you will pass it to `persist_annotation` in Step 3.

**Large session** (`window_paths` present): for each window N (0-indexed) in `window_paths` sequentially, dispatch all 4 agents in parallel:

- **executive-function**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {window_paths[N]}\n\nOutput path: {prefix}_executive_function_w{N}.json"`
- **metacognition**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {window_paths[N]}\n\nOutput path: {prefix}_metacognition_w{N}.json"`
- **memory-reasoning**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {window_paths[N]}\n\nOutput path: {prefix}_memory_reasoning_w{N}.json"`
- **user-mental-model**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {window_paths[N]}\n\nOutput path: {prefix}_user_mental_model_w{N}.json"`

After all windows complete, note the `{prefix}` and `window_count = len(window_paths)` — pass both to `persist_annotation` in Step 3.

---

**Step 3 — Persist**

Call `persist_annotation` with:
- `conversation_name`
- `output_prefix` — the `{prefix}` value from Step 2
- `parsed_path` — the `parsed_path` value returned by `resolve_transcript` in Step 1
- `window_count` — number of windows processed (`len(window_paths)` for large sessions; omit for single-window sessions)

The tool reads the agent output files, assembles annotation results, writes all excerpts to cognitive.db, and runs embedding-based sync to find the best cross-session match per excerpt.

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
