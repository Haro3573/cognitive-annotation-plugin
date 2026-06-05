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
- `status == "ready"` → use `transcript` (single session JSON string).
- `transcripts` present → batch mode; process each string through the remaining steps.

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

Call `classify_excerpts` with `conversation_name`, `annotation_results_new`, and `context_history` (the parsed transcript JSON array).

- If `task_count == 0` → set `relation_scores = {}` and go to Step 5.
- If tasks are returned → for each task, read the `evaluator_prompt` and apply it: given `subagent_comment` + `user_text` + `excerpt_text`, classify as `accepted`, `partially_matched`, or `rejected`. Build `relation_scores = {excerpt_id: score}`.

---

**Step 4 — Persist**

Call `persist_annotation` with `conversation_name`, `annotation_results_new`, `context_history`, and `relation_scores`.

---

**Step 5 — Output**

- **Single session**: show the combined annotation JSON, then the `persist_annotation` summary.
- **Batch**: print `✓ {conversation_name[:8]} — {processed} aligned, {skipped} skipped` per session. Print totals at the end.
