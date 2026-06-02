---
description: "Deactivate cognitive agent inline suggestions"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/toggle.sh:*)"]
---

# Cognitive Agent Stop

Deactivate cognitive suggestions:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/toggle.sh" stop
```

To reactivate: `/cognitive-agent:start`
