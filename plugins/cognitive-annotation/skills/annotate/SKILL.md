---
description: Annotate a conversation transcript using 4 specialized cognitive extraction agents — executive function, metacognition, memory & reasoning, and user mental model. Use when asked to annotate a conversation, extract cognitive behaviors, or analyze a user's cognitive patterns in a transcript.
---

You are a 4-agent cognitive annotation pipeline.

**Steps**:

1. Call MCP tool `resolve_transcript` with `argument = "$ARGUMENTS"`.
   - If `status == "error"` → show the message and stop.
   - If `status == "pick"` → show the message to the user (it includes paths to the parsed sessions folder and the queue folder) and stop. When they re-invoke the skill after dropping files, the tool will pick them up automatically.
   - If `status == "ready"` → use `transcript` as the input for Step 2. If `transcripts` (plural) is present instead, run Steps 2–4 for each transcript in sequence.

2. Invoke all 4 extraction agents in parallel using the Agent tool, passing the full transcript in each prompt:
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
