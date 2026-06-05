---
description: Annotate a conversation transcript using 4 specialized cognitive extraction agents — executive function, metacognition, memory & reasoning, and user mental model. Use when asked to annotate a conversation, extract cognitive behaviors, or analyze a user's cognitive patterns in a transcript. For batch annotation of all parsed sessions, call queue_all_sessions first then invoke with no argument.
---

You are a 4-agent cognitive annotation pipeline that runs end-to-end: extract → classify → write DB → export snapshot.

**Steps**:

1. Call MCP tool `resolve_transcript` with `argument = "$ARGUMENTS"`.
   - If `status == "error"` → show the message and stop.
   - If `status == "pick"` → show the message (it includes paths to the parsed sessions folder and the queue folder) and stop.
   - If `status == "ready"` → `transcript` is a single session JSON string. Run Steps 2–7 once.
   - If `transcripts` (plural) is present → batch run. For each transcript in sequence, run Steps 2–7, printing a one-line progress summary per session. After all sessions, print a batch total and stop.

2. Parse the transcript string as JSON to get `context_history` (list of message dicts). Extract `conversation_name` from `context_history[0]["conversation_name"]`.

3. Invoke all 4 extraction agents **in parallel** using the Agent tool, passing the full transcript string in each prompt:
   - **executive-function** agent: "Annotate the following transcript for executive function behaviors (planning, inhibition, shifting). Annotate HUMAN turns only.\n\n[transcript]"
   - **metacognition** agent: "Annotate the following transcript for metacognitive behaviors (knowledge of limits, confidence calibration, error monitoring, monitoring-control coupling). Annotate HUMAN turns only.\n\n[transcript]"
   - **memory-reasoning** agent: "Annotate the following transcript for memory and reasoning behaviors (domain knowledge injection, deductive/inductive/abductive/analogical reasoning). Annotate HUMAN turns only.\n\n[transcript]"
   - **user-mental-model** agent: "Annotate the following transcript for user mental model behaviors (system model updates, cooperation and persuasion). Annotate HUMAN turns only.\n\n[transcript]"

4. Combine all 4 results into `annotation_results_new`:
```json
{
  "executive_function": { ... },
  "metacognition": { ... },
  "memory_and_reasoning": { ... },
  "user_mental_model": { ... }
}
```

5. **Self-classify excerpts** (only if `context_history` contains messages with `role == "subagent"`):

   For each excerpt in `annotation_results_new`, compute its `excerpt_id`:
   ```
   conv_slug = conversation_name.lower(), replace all non-alphanumeric chars with "_"
   excerpt_id = "{category}__{subcategory}__{conv_slug}__turn_{turn_index}"
   ```
   where `category` maps as: `executive_function→executive-function`, `metacognition→metacognition`, `memory_and_reasoning→memory-reasoning`, `user_mental_model→user-mental-model`.

   Find the nearest preceding subagent message in `context_history` before the excerpt's `turn_index`. Read the matching evaluator prompt:
   - `executive_function` excerpts → `pipeline/outcome_processor/evaluators/executive-function.md`
   - `metacognition` excerpts → `pipeline/outcome_processor/evaluators/metacognition.md`
   - `memory_and_reasoning` excerpts → `pipeline/outcome_processor/evaluators/memory-reasoning.md`
   - `user_mental_model` excerpts → `pipeline/outcome_processor/evaluators/user-mental-model.md`

   Apply the evaluator: given the subagent comment + the user's subsequent text + the excerpt, classify as `accepted`, `partially_matched`, or `rejected`. Build:
   ```json
   { "excerpt_id": "accepted|partially_matched|rejected", ... }
   ```

   If no subagent turns exist in `context_history`, set `relation_scores = {}`.

6. Call `build_subagent_map` with `conversation_name`. Use the returned map as `subagent_map`.

7. Call `report_decision_outcome` with:
   - `conversation_name`
   - `annotation_results_new` (from Step 4)
   - `subagent_map` (from Step 6)
   - `context_history` (from Step 2)
   - `relation_scores` (from Step 5)

8. Call `export_session_snapshot` with `conversation_name`.

9. **Output**:
   - **Single session**: print the combined annotation JSON, the DB write summary from `report_decision_outcome`, and a confirmation that the snapshot was exported.
   - **Batch**: print one line per session: `✓ {conversation_name[:8]} — {N} excerpts, {processed} aligned, snapshot exported` or `✗ {conversation_name[:8]} — {error}`. After all sessions: `Batch complete: N sessions processed.`
