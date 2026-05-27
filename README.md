# cognitive-annotation

A Claude Code plugin that annotates conversation transcripts with cognitive behavioral evidence across four domains: executive function, metacognition, memory & reasoning, and user mental model.

## Installation

```
/plugin install github:Haro3573/cognitive-annotation-plugin
```

## Usage

Pass a file path:
```
/cognitive-annotation:annotate sample_conversation.json
```

Or paste a transcript directly into the conversation, then run:
```
/cognitive-annotation:annotate
```

If no transcript is provided, the plugin will ask you for one.

## What it extracts

| Agent | Extracts |
|---|---|
| **Executive Function** | Planning behavior, inhibition behavior, shifting behavior |
| **Metacognition** | Knowledge of limits, confidence calibration, error monitoring, monitoring→control coupling |
| **Memory & Reasoning** | Domain knowledge injection, deductive / inductive / abductive / analogical reasoning |
| **User Mental Model** | System model updates, cooperation and persuasion |

Each extraction includes an evidence quote, turn index, confidence score (≥ 0.3), mundane alternative explanation, and reasoning for the label.

## Output

A combined JSON object with one key per agent, plus a plain-language summary of notable findings.

```json
{
  "executive_function": {
    "planning_behavior": [ ... ],
    "inhibition_behavior": [ ... ],
    "shifting_behavior": [ ... ],
    "null_findings": "..."
  },
  "metacognition": { ... },
  "memory_and_reasoning": { ... },
  "user_mental_model": { ... }
}
```

Empty sub-categories include a `null_findings` string explaining what was searched for and not found — a blank with explanation is more useful than a forced extraction.

---

## System Architecture

### Overview

The plugin is a pure Claude Code component — no Python, no API key, no external dependencies. It consists of one orchestrator skill and four specialized subagents.

```
User
 │
 │  /cognitive-annotation:annotate <transcript>
 ▼
┌─────────────────────────────────────────┐
│         SKILL: annotate                 │
│  (runs in main Claude Code thread)      │
│                                         │
│  1. Resolves transcript source          │
│  2. Spawns 4 subagents via Agent tool   │
│  3. Combines results into JSON          │
└────────┬────────┬────────┬──────────────┘
         │        │        │        │
         ▼        ▼        ▼        ▼
   ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐
   │  A1  │ │  A2  │ │  A3  │ │  A4  │
   │ Exec │ │Meta- │ │Mem & │ │User  │
   │ Func │ │cogn. │ │Reas. │ │Model │
   └──────┘ └──────┘ └──────┘ └──────┘
```

### Components

**`skills/annotate/SKILL.md`** — the entry point. Runs in the main Claude Code conversation thread. Resolves the transcript (from a file path, inline text, or conversation context), then sequentially invokes each of the four subagents via the `Agent` tool, passing the full transcript in each call. Combines the four results into a single JSON structure.

**`agents/*.md`** — four subagent definitions. Each runs in its own isolated context window with:
- A specialized system prompt grounded in cognitive psychology theory
- `tools: []` — no file access; the transcript arrives entirely in the prompt
- `model: sonnet` — Sonnet balances annotation depth with speed

Subagents are invoked sequentially (Claude Code subagents cannot run in parallel within a single session). Each returns a JSON object; the skill merges them.

### Execution flow

```
1. /cognitive-annotation:annotate <path>
        │
2. Skill reads file at <path>
        │
3. Skill calls Agent tool → executive-function subagent
        │   subagent reasons over transcript
        │   returns { executive_function_behavior: { ... } }
        │
4. Skill calls Agent tool → metacognition subagent
        │   returns { metacognition_behavior: { ... } }
        │
5. Skill calls Agent tool → memory-reasoning subagent
        │   returns { memory_and_reasoning_behavior: { ... } }
        │
6. Skill calls Agent tool → user-mental-model subagent
        │   returns { user_mental_model_behavior: { ... } }
        │
7. Skill merges all four → combined JSON + summary
```

### Annotation design principles

- **Liberal extraction**: agents extract at confidence ≥ 0.3 and report their certainty honestly. False negatives are unrecoverable in a dataset; false positives can be filtered downstream.
- **Mundane alternative**: every extraction requires a mundane alternative explanation. The cognitive label is kept only if the mundane reading is less plausible.
- **No schema-shape filling**: agents are explicitly instructed not to produce one extraction per sub-category to satisfy schema shape. An honest zero with a specific `null_findings` explanation is more scientifically valuable than an invented extraction.
- **HUMAN turns only**: all four agents annotate human turns exclusively. AI turns provide context but are not coded.

### Relation to the Python SDK pipeline

This plugin is the Claude Code-native form of the same pipeline. A standalone Python version (`Cognitive_Annotation/main.py`) using the Claude Agent SDK runs the same four agents via `asyncio.gather()` for true parallel execution and writes structured output to `results.json`. Use the plugin for interactive annotation within Claude Code; use the Python pipeline for batch processing or automation.

### Theoretical grounding

| Agent | Primary theory |
|---|---|
| Executive Function | Updating / Inhibition / Shifting model (Miyake et al., 2000) |
| Metacognition | Monitoring and Control framework (Nelson & Narens, 1990) |
| Memory & Reasoning | Peirce's inference types; Structure-Mapping Theory (Gentner, 1983) |
| User Mental Model | Mental models of interactive systems (Norman, 1983) |
