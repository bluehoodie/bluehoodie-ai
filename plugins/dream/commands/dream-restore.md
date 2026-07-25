---
name: dream-restore
description: Undo the last dream — restore memory from the snapshot taken before it ran
allowed-tools: Bash
---

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/dream.py" restore
```

Show the output to the user. This replaces the memory directory with the snapshot
taken when the last dream launched, discarding everything written since — both
what the dream changed and any memory saved afterwards. There is one snapshot per
project, so the previous dream cannot be undone once a newer one has launched.
