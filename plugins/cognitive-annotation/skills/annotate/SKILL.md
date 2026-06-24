---
description: Annotate a conversation transcript using 4 cognitive extraction agents — extracts behavioral excerpts, then uses embedding similarity to match each excerpt to the most similar past excerpt in the same subcategory across sessions. For batch annotation, call queue_all_sessions first then invoke with no argument.
model: haiku
---

You are a 4-agent cognitive annotation pipeline. Run all steps for every session.

---

**Step 1 — Resolve transcript**

> **Token note:** Pass a file *path* as the argument (e.g. `/path/to/session.jsonl`), not an @mention. @mention expansion inlines the full raw JSONL into context before this tool call — 10–100× larger than the stripped view the server writes to disk. If `$ARGUMENTS` looks like expanded NDJSON content rather than a path, warn the user and stop; ask them to pass the file path directly or use the queue system.

Call `resolve_transcript` with `argument = "$ARGUMENTS"`.
- `status == "error"` → show the error and stop.
- `status == "pick"` and `$ARGUMENTS` is non-empty → show the message and stop (the argument wasn't a valid session file).
- `status == "pick"` and `$ARGUMENTS` is empty → call `queue_all_sessions` (no args) first, then call `resolve_transcript` again with `argument = ""`. If the second call also returns `pick` (nothing available to queue), show the message and stop.
- `status == "ready"` → proceed to Step 2 using `sessions` and `count`.

---

**Step 2 — Extract cognitive behaviors + generate summary (batch coordinator)**

**Step 2-A — Start coordinator**

Call `batch_start` with `sessions` from Step 1.
- If response has `done: true` → skip to Step 4 and show `summary_md`.
- Otherwise record `job_id` and `next_session`.

**Step 2-B — Per-session subagent loop**

While `next_session` is available:

1. Dispatch a fresh **Haiku subagent** with this prompt (substitute values from `next_session`):

   ```
   You are a single-session annotation runner. Annotate exactly one session, then stop.

   conversation_name: {next_session.conversation_name}
   parsed_path: {next_session.parsed_path}
   output_prefix: {next_session.output_prefix}
   window_paths: {next_session.window_paths}

   Steps:
   1. If window_paths is empty (single mode): dispatch all 5 agents in parallel
      (executive-function, metacognition, memory-reasoning, user-mental-model,
      summarizer) using parsed_path.
      If window_paths is non-empty (windowed mode): for window 0, dispatch all
      5 agents in parallel using window_paths[0] (annotation agents use
      window_paths[0] as their path; summarizer uses parsed_path). For each
      subsequent window, dispatch only the 4 annotation agents in parallel
      (no summarizer).
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

**Step 3 — Update wiki**

Invoke `/cognitive-annotation:wiki-ingest` to sync the wiki with the newly annotated session(s). Call once after all sessions complete (not per-session — defers overview rebuild to the end).

---

**Step 4 — Output**

Display the `summary_md` returned by the final `batch_advance` call (or `batch_start` if sessions was empty), then the wiki-ingest summary.
