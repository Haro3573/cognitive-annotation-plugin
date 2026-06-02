---
description: "Activate cognitive agent inline suggestions for this session"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/toggle.sh:*)"]
---

# Cognitive Agent Start

Activate real-time cognitive suggestions:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/toggle.sh" start
```

Requires `$CLAUDE_PROJECT_DIR/.cognitive/session.json` to exist. If not, run the DB Block pipeline first by mentioning a `.jsonl` session file in your prompt.

A 💡 cognitive insight will appear after each AI response, shaped by your Cognitive Profile.

To deactivate: `/cognitive-agent:stop`
