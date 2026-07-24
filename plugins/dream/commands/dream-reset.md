---
name: dream-reset
description: Reset dream consolidation state — clears lock and nag files so gates reopen
allowed-tools: Bash
---

Reset the dream plugin state:

```bash
rm -f "$HOME/.claude/dream-plugin-state/.consolidate-lock" "$HOME/.claude/dream-plugin-state/.last-nag"
echo "Dream state reset. Gates will reopen on next session."
```
