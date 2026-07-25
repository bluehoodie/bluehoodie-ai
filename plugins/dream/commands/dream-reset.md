---
name: dream-reset
description: Reset dream consolidation state — clears the lock so the gates reopen
allowed-tools: Bash
---

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/dream.py" reset
```

Show the output to the user. To reset *every* project instead, remove
`$HOME/.claude/dream-plugin-state` entirely — confirm first, since that discards
every project's consolidation history.
