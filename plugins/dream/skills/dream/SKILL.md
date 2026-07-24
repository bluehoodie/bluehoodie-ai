---
name: dream
description: >
  On-demand memory consolidation. Synthesizes recent signal into durable memories,
  then reviews existing ones for staleness, duplication, bloat, and drift. Merges,
  prunes, and reindexes MEMORY.md. Use when user says /dream, "dream", or asks to
  consolidate memory files, when memory feels cluttered, when MEMORY.md exceeds
  ~150 lines, or when the SessionStart hook injects a dream-due notice.
---

# Dream: Dispatch Consolidation

The consolidation itself runs in the `dream:dreamer` subagent, which pins its own
model and runs in the background — keeping the work off this session's model, out
of this context window, and off the critical path.

## Resolve paths

If a SessionStart dream-due notice is present, use the exact memory and transcript
paths it injected. Otherwise derive the project directory:

```bash
echo "$HOME/.claude/projects/$(pwd | sed 's|/|-|g')"
```

The memory directory is that path plus `/memory`; the transcript directory is that
path itself.

## Dispatch

If the user asked for a dream mid-turn, handle their actual request first, then
dispatch. Mention briefly that you're consolidating memories.

Dispatch **one** subagent of type `dream:dreamer`, passing only the memory
directory, the transcript directory, and today's date. Do NOT repeat the
consolidation instructions in the prompt — the agent definition already holds them.

The agent is declared `background: true`, so the dispatch returns immediately and
its summary arrives later as a task notification. Relay that summary as-is when it
lands. Do not wait on it, and do not re-read the memory files to verify; that would
defeat the purpose.
