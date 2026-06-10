---
description: Annotate a conversation transcript using 4 specialized cognitive extraction agents — executive function, metacognition, memory & reasoning, and user mental model. Use when asked to annotate a conversation, extract cognitive behaviors, or analyze a user's cognitive patterns in a transcript. For batch annotation of all parsed sessions, call queue_all_sessions first then invoke with no argument.
---

You are a 4-agent cognitive annotation pipeline. Run all steps for every session.

**For batch runs** (`transcripts` array returned): repeat Steps 1–5 for each transcript in sequence, printing one progress line per session. Print a total when all sessions are done.

---

**Step 1 — Resolve transcript**

Call `resolve_transcript` with `argument = "$ARGUMENTS"`.
- `status == "error"` → show the error and stop.
- `status == "pick"` → show the message (includes paths to browse and queue folder) and stop.
- `status == "ready"` → use `transcript` (single session JSON string). Store `sidecar_path` from the response (may be null).
- `transcripts` present → batch mode; process each string through the remaining steps. Store `sidecar_paths` array (parallel to `transcripts`).

---

**Step 2 — Extract cognitive behaviors (4 agents in parallel)**

Parse the transcript string as JSON. Pass it to all 4 agents simultaneously:

- **executive-function**: "Annotate the following transcript for executive function behaviors (planning, inhibition, shifting). Annotate HUMAN turns only.\n\n[transcript]"
- **metacognition**: "Annotate the following transcript for metacognitive behaviors (knowledge of limits, confidence calibration, error monitoring, monitoring-control coupling). Annotate HUMAN turns only.\n\n[transcript]"
- **memory-reasoning**: "Annotate the following transcript for memory and reasoning behaviors (domain knowledge injection, deductive/inductive/abductive/analogical reasoning). Annotate HUMAN turns only.\n\n[transcript]"
- **user-mental-model**: "Annotate the following transcript for user mental model behaviors (system model updates, cooperation and persuasion). Annotate HUMAN turns only.\n\n[transcript]"

Combine results into `annotation_results_new`:
```json
{
  "executive_function": { ... },
  "metacognition": { ... },
  "memory_and_reasoning": { ... },
  "user_mental_model": { ... }
}
```

---

**Step 3 — Prepare classification**

Call `classify_excerpts` with `conversation_name`, `annotation_results_new`, and `context_history` (the parsed transcript JSON array). If `sidecar_path` from Step 1 is non-null, pass it as `sidecar_path`.

- If `task_count == 0` → set `relation_scores = {}` and go to Step 5.
- If tasks are returned → dispatch the **classifier** agent with the full task list:

  ```
  "Classify the following behavioral excerpts. Return relation_scores JSON.\n\n[task list as JSON array]"
  ```

  The agent applies each task's `evaluator_prompt` to its `(subagent_comment, user_text, excerpt_text)` triplet and returns `{"relation_scores": {excerpt_id: score}}`. Extract `relation_scores` from the agent's output.

---

**Step 4 — Persist**

Call `persist_annotation` with `conversation_name`, `annotation_results_new`, `context_history`, and `relation_scores`.

---

**Step 5 — Update wiki**

Invoke `/cognitive-annotation:wiki-ingest` to sync the wiki with the newly annotated session(s).

- **Single session**: call immediately after Step 4.
- **Batch**: call once after all sessions complete (not per-session — defers overview rebuild to the end).

---

**Step 6 — Output**

- **Single session**: show the `persist_annotation` summary, then the wiki ingest summary.
- **Batch**: print `✓ {conversation_name[:8]} — {processed} aligned, {skipped} skipped` per session. Print totals and wiki ingest summary at the end.
