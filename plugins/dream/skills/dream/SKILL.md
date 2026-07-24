---
name: dream
description: >
  On-demand memory consolidation. Synthesizes recent signal into durable memories,
  then reviews existing ones for staleness, duplication, bloat, and drift. Merges,
  prunes, and reindexes MEMORY.md. Use when user says /dream, "dream", or asks to
  consolidate memory files, when memory feels cluttered, when MEMORY.md exceeds
  ~150 lines, or when the SessionStart hook injects a dream-due notice.
---

# Dream: Memory Consolidation

You are performing a dream — a reflective pass over your memory files.
Synthesize recent experience into durable, well-organized memories so that
future sessions can orient quickly without repeating discoveries.

## Paths

**Memory directory:** `~/.claude/projects/<project>/memory/`
This directory already exists — write to it directly with the Write tool
(do not run `mkdir` or check for its existence).

**Session transcripts:** `~/.claude/projects/<project>/` — large JSONL files.
Grep them narrowly; never read one whole.

`<project>` is the launch directory with every `/` replaced by `-`
(`/Users/me/code/app` → `-Users-me-code-app`). When the SessionStart hook
triggered this dream, it injected both exact paths — use those instead of
deriving them. Otherwise:

```bash
echo "$HOME/.claude/projects/$(pwd | sed 's|/|-|g')/memory"
```

**Only write inside the memory directory.** A dream never modifies project
code, config, or anything else in the working tree.

## Phase 1 — Orient

1. `ls` the memory directory to see what already exists
2. Read `MEMORY.md` to understand the current index; note if over 150 lines
3. Skim existing topic files (first ~30 lines of each) to gauge coverage and
   freshness, so you improve them rather than creating duplicates
4. If `logs/` or `sessions/` subdirectories exist (assistant-mode layout),
   list them and review the most recent entries

## Phase 2 — Gather recent signal

Look for new information worth persisting. Sources in priority order:

1. **Daily logs** — `logs/YYYY/MM/YYYY-MM-DD.md` if present. This is the
   append-only stream and the richest source; read the entries added since
   the last consolidation.
2. **Existing memories that drifted** — facts that contradict what the
   codebase or git history shows now.
3. **Transcript search** — only when you need a specific detail you already
   suspect matters (e.g. "what was the error from yesterday's build
   failure?"). Grep narrow terms:

   ```bash
   grep -rn "<narrow term>" ~/.claude/projects/<project>/ --include="*.jsonl" | tail -50
   ```

Do not exhaustively read transcripts. Look only for things you already
suspect matter.

## Phase 3 — Audit and consolidate

First audit **each** existing memory file:

| Check | Action |
|-------|--------|
| **Staleness** | Does this fact still match the codebase? Grep/read to verify key claims. If wrong, update or delete. |
| **Duplication** | Do two files cover the same topic? Merge the pair. |
| **Bloat** | Is any MEMORY.md entry over ~200 chars? Demote it — move detail into the topic file, shorten the index line. |
| **Missing links** | Are there `[[name]]` references to memories that don't exist? Create the referenced memory or remove the dead link. |
| **Type drift** | Does `metadata.type` still match the content? (e.g. a "project" memory that's really "feedback") |
| **Date rot** | Any relative dates ("last week", "recently") that should be absolute? |

Then write the result, at the **top level** of the memory directory:

- **Persist new signal from Phase 2** as new memory files, or by merging it
  into the existing topic file it belongs to. Prefer merging — a near-duplicate
  is worse than a longer file.
- **Use the memory file format and type conventions from the auto-memory
  section of your system prompt.** That section is the source of truth for what
  to save, how to structure the frontmatter, and what NOT to save.
- **Fix stale facts** to match current code/git state. If a memory is entirely
  obsolete, delete the file.
- **Convert relative dates** to absolute dates, using today's date as reference.
- **Remove memories that violate the save rules** — code structure derivable by
  reading files, git history available via `git log`, fixes already visible in
  committed code, anything already in CLAUDE.md.
- **Fix type fields** and update descriptions to match current content.
- **Resolve contradictions** — trust current code over old memory.

## Phase 4 — Prune and index

Update `MEMORY.md`. It is an **index**, not a dump — never write memory content
into it.

- Each entry is one line under ~150 characters: `- [Title](file.md) — one-line hook`
- Stay under 200 lines total and under ~25KB
- Remove pointers to files that are now deleted, stale, wrong, or superseded
- Add pointers to memories created this pass
- Sort semantically by topic, not chronologically
- Verify every link target exists

Then stamp the consolidation so the time gate resets:

```bash
mkdir -p ~/.claude/dream-plugin-state && touch ~/.claude/dream-plugin-state/.consolidate-lock
```

## Rules

- Do NOT create memories about the current task or conversation — dream
  consolidates past sessions, it does not journal this one
- Do NOT read full JSONL transcripts — grep narrowly for specific terms only
- If everything is already tight and nothing changed, say "Memory is clean —
  no changes needed", stamp the lock, and stop
- Return a brief summary: files created, merged, updated, deleted, and index
  lines changed

## When Triggered by Hook

If a SessionStart notice says consolidation is due, handle the user's request
first, then run this consolidation at the end of your turn. Mention briefly that
you're consolidating memories.
