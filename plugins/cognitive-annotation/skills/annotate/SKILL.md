---
description: Annotate a conversation transcript using 4 cognitive extraction agents — extracts behavioral excerpts, then uses embedding similarity to match each excerpt to the most similar past excerpt in the same subcategory across sessions. For batch annotation, call queue_all_sessions first then invoke with no argument.
---

You are a 4-agent cognitive annotation pipeline. Run all steps for every session.

**For batch runs** (`mode: "batch"` returned in Step 1): repeat Steps 2–3 for each session in `sessions`, then run Steps 4–5 once at the end.

---

**Step 1 — Resolve transcript**

> **Token note:** Pass a file *path* as the argument (e.g. `/path/to/session.jsonl`), not an @mention. @mention expansion inlines the full raw JSONL into context before this tool call — 10–100× larger than the stripped view the server writes to disk. If `$ARGUMENTS` looks like expanded NDJSON content rather than a path, warn the user and stop; ask them to pass the file path directly or use the queue system.

Call `resolve_transcript` with `argument = "$ARGUMENTS"`.
- `status == "error"` → show the error and stop.
- `status == "pick"` and `$ARGUMENTS` is non-empty → show the message and stop (the argument wasn't a valid session file).
- `status == "pick"` and `$ARGUMENTS` is empty → call `queue_all_sessions` (no args) first, then call `resolve_transcript` again with `argument = ""`. If the second call also returns `pick` (nothing available to queue), show the message and stop.
- `status == "ready"` → proceed to Step 2 using the `mode` field.

---

**Step 2 — Extract cognitive behaviors (4 agents in parallel)**

Use `output_prefix` from the Step 1 result — do not construct temp paths manually.

**mode `"single"`**: dispatch all 4 agents simultaneously using `parsed_path` and `output_prefix`:

- **executive-function**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {parsed_path}\n\nOutput path: {output_prefix}_executive_function.json"`
- **metacognition**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {parsed_path}\n\nOutput path: {output_prefix}_metacognition.json"`
- **memory-reasoning**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {parsed_path}\n\nOutput path: {output_prefix}_memory_reasoning.json"`
- **user-mental-model**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {parsed_path}\n\nOutput path: {output_prefix}_user_mental_model.json"`

**mode `"windowed"`**: for each path in `window_paths` sequentially (position index i starting at 0), dispatch all 4 agents in parallel:

- **executive-function**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {window_paths[i]}\n\nOutput path: {output_prefix}_executive_function_w{i}.json"`
- **metacognition**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {window_paths[i]}\n\nOutput path: {output_prefix}_metacognition_w{i}.json"`
- **memory-reasoning**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {window_paths[i]}\n\nOutput path: {output_prefix}_memory_reasoning_w{i}.json"`
- **user-mental-model**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {window_paths[i]}\n\nOutput path: {output_prefix}_user_mental_model_w{i}.json"`

**mode `"batch"`**: for each `session` object in `sessions`:
- If `session.window_paths` is empty → dispatch as **single** using `session.parsed_path` and `session.output_prefix`.
- If `session.window_paths` is non-empty → dispatch as **windowed** using `session.window_paths` and `session.output_prefix`.
- If any agent call in Step 2 or `persist_annotation` in Step 3 returns an error for a session, record the error and continue to the next session — do not stop the batch.

---

**Step 3 — Persist**

Call `persist_annotation` with:
- `output_prefix` — the value from Step 1 (for batch: each session's `output_prefix`)

---

**Step 4 — Update wiki**

Invoke `/cognitive-annotation:wiki-ingest` to sync the wiki with the newly annotated session(s).

- **Single/windowed**: call immediately after Step 3.
- **Batch**: call once after all sessions complete (not per-session — defers overview rebuild to the end).

---

**Step 5 — Output**

- **Single/windowed**: show the `persist_annotation` summary, then the wiki ingest summary.
- **Batch**: for each session:
  - If Step 2 or Step 3 failed → print `✗ {conversation_name[:8]} — failed ({error_message})`
  - Otherwise → print `✓ {conversation_name[:8]} — {excerpts_written} written, {excerpts_updated} updated`
  - Print total session count and wiki ingest summary at the end.
