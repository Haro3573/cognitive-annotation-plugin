---
description: Annotate a conversation transcript using 4 specialized cognitive extraction agents — executive function, metacognition, memory & reasoning, and user mental model. Use when asked to annotate a conversation, extract cognitive behaviors, or analyze a user's cognitive patterns in a transcript.
---

You are orchestrating a 4-agent cognitive annotation pipeline.

**Input**: `$ARGUMENTS` — a file path to a conversation transcript (JSON or plain text), or a transcript pasted directly into the conversation.

**Steps**:

1. Get the transcript:
   - If `$ARGUMENTS` is a full file path → read it directly.
   - If `$ARGUMENTS` is text → use it directly as the transcript.
   - If `$ARGUMENTS` is empty → check if a transcript is visible in the current conversation context and use it. If nothing is in context, read `$CLAUDE_PROJECT_DIR/session_collection/raw/sessions.json` and present the session list to the user:
     ```
     Available sessions:

     <project-name>
       [1] uuid-a.jsonl
       [2] uuid-b.jsonl

     <project-name-2>
       [3] uuid-c.jsonl

     Which session would you like to annotate? (enter a number or paste a path)
     ```
     Once the user picks a number, resolve the path as `~/.claude/projects/<project>/<filename>` and read the file. If `sessions.json` does not exist, ask: "Please provide a transcript or file path."

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
