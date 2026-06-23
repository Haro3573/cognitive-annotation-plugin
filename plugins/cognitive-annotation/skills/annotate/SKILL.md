---
description: Annotate a conversation transcript using 4 cognitive extraction agents — extracts behavioral excerpts, then uses embedding similarity to match each excerpt to the most similar past excerpt in the same subcategory across sessions. For batch annotation, call queue_all_sessions first then invoke with no argument.
model: haiku
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

**Step 2 — Extract cognitive behaviors + generate summary (agents in parallel)**

Use `output_prefix` from the Step 1 result — do not construct temp paths manually.

**mode `"single"`**: dispatch all 5 agents simultaneously using `parsed_path`, `conversation_name`, and `output_prefix`:

- **executive-function**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {parsed_path}\n\nconversation_name: {conversation_name}\nparsed_path: {parsed_path}"`
- **metacognition**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {parsed_path}\n\nconversation_name: {conversation_name}\nparsed_path: {parsed_path}"`
- **memory-reasoning**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {parsed_path}\n\nconversation_name: {conversation_name}\nparsed_path: {parsed_path}"`
- **user-mental-model**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {parsed_path}\n\nconversation_name: {conversation_name}\nparsed_path: {parsed_path}"`
- **summarizer**: `"Read transcript from: {parsed_path}\n\nOutput path: {output_prefix}_summary.json"`

**mode `"windowed"`**: for each path in `window_paths` sequentially (position index i starting at 0), dispatch all 4 annotation agents in parallel. Additionally, dispatch the **summarizer once on `parsed_path`** (not per window) alongside window 0's agents:

- For window 0 (i=0), dispatch all 5 in parallel:
  - **executive-function**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {window_paths[0]}\n\nconversation_name: {conversation_name}\nparsed_path: {window_paths[0]}"`
  - **metacognition**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {window_paths[0]}\n\nconversation_name: {conversation_name}\nparsed_path: {window_paths[0]}"`
  - **memory-reasoning**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {window_paths[0]}\n\nconversation_name: {conversation_name}\nparsed_path: {window_paths[0]}"`
  - **user-mental-model**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {window_paths[0]}\n\nconversation_name: {conversation_name}\nparsed_path: {window_paths[0]}"`
  - **summarizer**: `"Read transcript from: {parsed_path}\n\nOutput path: {output_prefix}_summary.json"`
- For each subsequent window (i>0), dispatch the 4 annotation agents in parallel (no summarizer):
  - **executive-function**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {window_paths[i]}\n\nconversation_name: {conversation_name}\nparsed_path: {window_paths[i]}"`
  - **metacognition**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {window_paths[i]}\n\nconversation_name: {conversation_name}\nparsed_path: {window_paths[i]}"`
  - **memory-reasoning**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {window_paths[i]}\n\nconversation_name: {conversation_name}\nparsed_path: {window_paths[i]}"`
  - **user-mental-model**: `"Annotate HUMAN turns only — skip any turn where context_only is true.\n\nRead transcript from: {window_paths[i]}\n\nconversation_name: {conversation_name}\nparsed_path: {window_paths[i]}"`

**mode `"batch"`**:

**Step 2-batch-A — Start coordinator**

Call `batch_start` with `sessions` from Step 1.
- If response has `done: true` → skip to Step 5 and show `summary_md`.
- Otherwise record `job_id` and `next_session`.

**Step 2-batch-B — Per-session subagent loop**

While `next_session` is available:

1. Dispatch a fresh **Haiku subagent** with this prompt (substitute values from `next_session`):

   ```
   You are a single-session annotation runner. Annotate exactly one session, then stop.

   conversation_name: {next_session.conversation_name}
   parsed_path: {next_session.parsed_path}
   output_prefix: {next_session.output_prefix}
   window_paths: {next_session.window_paths}

   Steps:
   1. Dispatch all 5 agents in parallel (executive-function, metacognition,
      memory-reasoning, user-mental-model, summarizer) using parsed_path if
      window_paths is empty (single mode), or per-window using window_paths
      (windowed mode) — matching the single/windowed dispatch rules in this skill.
   2. Call persist_annotation with output_prefix.
   3. Return ONLY this JSON (no other text):
      {"conversation_name": "...", "success": true, "excerpts_written": N, "excerpts_updated": N, "error": ""}
      On failure: {"conversation_name": "...", "success": false, "excerpts_written": 0, "excerpts_updated": 0, "error": "<message>"}
   ```

2. Parse the subagent JSON result. If the result is missing or unparseable, synthesize:
   `{"conversation_name": "{next_session.conversation_name}", "success": false, "excerpts_written": 0, "excerpts_updated": 0, "error": "subagent returned no result"}`

3. Call `batch_advance` with `job_id` and the result object.
   - Response has `next_session` → update `next_session` and continue the loop.
   - Response has `done: true` → record `summary_md`, exit loop.
   - Response is an error string (e.g. `"Error: ValueError: Unknown job_id"`) → stop the loop, display the error and whatever results were collected so far.

---

**Step 3 — Persist** *(single and windowed modes only — batch handles persist inside each subagent)*

Call `persist_annotation` with:
- `output_prefix` — the value from Step 1

---

**Step 4 — Update wiki**

Invoke `/cognitive-annotation:wiki-ingest` to sync the wiki with the newly annotated session(s).

- **Single/windowed**: call immediately after Step 3.
- **Batch**: call once after all sessions complete (not per-session — defers overview rebuild to the end).

---

**Step 5 — Output**

- **Single/windowed**: show the `persist_annotation` summary, then the wiki ingest summary.
- **Batch**: display the `summary_md` returned by the final `batch_advance` call, then the wiki-ingest summary.
