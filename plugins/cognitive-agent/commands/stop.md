---
description: "Deactivate cognitive agent inline suggestions"
allowed-tools: ["Bash(test -f .claude/cognitive-agent-active:*)", "Bash(rm .claude/cognitive-agent-active)"]
---

# Cognitive Agent Stop

1. Check if `.claude/cognitive-agent-active` exists:
   `test -f .claude/cognitive-agent-active && echo EXISTS || echo NOT_FOUND`

2. If NOT_FOUND: Say "Cognitive agent is not active."

3. If EXISTS:
   - Remove it: `rm .claude/cognitive-agent-active`
   - Say "Cognitive agent deactivated."
