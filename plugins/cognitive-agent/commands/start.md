---
description: "Activate cognitive agent inline suggestions for this session"
argument-hint: "<path/to/session.json> <path/to/session.index.md>"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh:*)"]
---

# Cognitive Agent Start

Execute the setup script to activate the cognitive agent for this session:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" $ARGUMENTS
```

The stop hook is now active. After each AI response, a lightweight 💡 cognitive insight will appear as system context, shaped by your Cognitive Profile snapshot.

To deactivate: `/cognitive-agent:stop`
