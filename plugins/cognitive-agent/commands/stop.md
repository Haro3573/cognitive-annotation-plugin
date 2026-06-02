---
description: "Pause cognitive agent inline suggestions for this session"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/toggle.sh:*)"]
---

# Cognitive Agent Stop

Pause suggestions for the current session:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/toggle.sh" stop
```

Suggestions resume automatically in the next Claude Code session. To re-enable now: `/cognitive-agent:start`
