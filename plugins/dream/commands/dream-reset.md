---
name: dream-reset
description: Reset dream consolidation state — clears lock and nag files so gates reopen
allowed-tools: Bash
---

Reset the dream plugin state for the current project. State is per-project, keyed
by the launch directory slugified with every `/` replaced by `-`:

```bash
slug="$(printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}" | sed 's|/|-|g')"
rm -rf "$HOME/.claude/dream-plugin-state/${slug}"
echo "Dream state reset for ${slug}. Gates will reopen on next session."
```

If the user asks to reset *every* project, remove `$HOME/.claude/dream-plugin-state`
entirely instead — confirm with them first, since it discards every project's
consolidation history.
