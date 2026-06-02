---
description: Annotate a conversation transcript using 4 specialized cognitive extraction agents — executive function, metacognition, memory & reasoning, and user mental model. Use when asked to annotate a conversation, extract cognitive behaviors, or analyze a user's cognitive patterns in a transcript.
---

You are orchestrating a 4-agent cognitive annotation pipeline.

**Input**: `$ARGUMENTS` — a file path to a conversation transcript (JSON or plain text), or a transcript pasted directly into the conversation.

**Steps**:

1. Determine the transcript source:
   - If `$ARGUMENTS` is a bare filename (with or without leading `@`) ending in `.jsonl` → strip the `@` if present. **Use the Bash tool** to run these commands in order, stopping at the first non-empty result:
     1. `find "${COGNITIVE_SESSIONS_DIR:-}" -maxdepth 2 -name "<filename>" 2>/dev/null | head -1` — only if `$COGNITIVE_SESSIONS_DIR` is set
     2. `find "$CLAUDE_PROJECT_DIR" -maxdepth 4 -name "<filename>" 2>/dev/null | head -1`
     Take the result as the absolute path and pass it to `Read`. Do **not** guess paths or use prior context — always run these Bash commands.
   - If `$ARGUMENTS` is a full file path → read the file directly.
   - If `$ARGUMENTS` is plain text → use it directly as the transcript.
   - If `$ARGUMENTS` is empty → check if a transcript is visible in the current conversation context.
   - If nothing is available → **stop and ask**: "Please provide a transcript. You can either paste it here or give me a file path, e.g. `/cognitive-annotation:annotate sample_conversation.json`."

2. Invoke all 4 extraction agents one by one using the Agent tool, passing the full transcript in each prompt:
   - Use the **executive-function** agent: "Annotate the following transcript for executive function behaviors (planning, inhibition, shifting). Annotate HUMAN turns only.\n\n[transcript]"
   - Use the **metacognition** agent: "Annotate the following transcript for metacognitive behaviors (knowledge of limits, confidence calibration, error monitoring, monitoring-control coupling). Annotate HUMAN turns only.\n\n[transcript]"
   - Use the **memory-reasoning** agent: "Annotate the following transcript for memory and reasoning behaviors (domain knowledge injection, deductive/inductive/abductive/analogical reasoning). Annotate HUMAN turns only.\n\n[transcript]"
   - Use the **user-mental-model** agent: "Annotate the following transcript for user mental model behaviors (system model updates, cooperation and persuasion). Annotate HUMAN turns only.\n\n[transcript]"

3. Combine all 4 results into a single JSON structure:
```json
{
  "executive_function": { ... },
  "metacognition": { ... },
  "memory_and_reasoning": { ... },
  "user_mental_model": { ... }
}
```

4. Present the combined JSON, followed by a brief plain-language summary of the most notable findings across all 4 agents.
