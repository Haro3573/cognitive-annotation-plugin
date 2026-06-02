---
description: "Re-enable cognitive agent inline suggestions"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/toggle.sh:*)"]
---

# Cognitive Agent Start

Re-enable suggestions if they were paused with `/cognitive-agent:stop`:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/toggle.sh" start
```

If `$CLAUDE_PROJECT_DIR/.cognitive/session.json` exists, the agent is now active and a 💡 cognitive insight will appear after each AI response.

To pause: `/cognitive-agent:stop`
