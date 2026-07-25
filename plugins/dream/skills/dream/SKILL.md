---
name: dream
description: >
  Memory consolidation. Synthesizes recent signal into durable memories, then
  reviews existing ones for staleness, duplication, bloat, and drift. Merges,
  prunes, and reindexes MEMORY.md. Use when the user says /dream, "dream", or
  asks to consolidate memory files, when memory feels cluttered, or when
  MEMORY.md exceeds ~150 lines.
---

# Dream: Memory Consolidation

You are performing a dream — a reflective pass over the memory files for this
project. Synthesize recent experience into durable, well-organized memories so
that future sessions can orient quickly without repeating discoveries.

The SessionStart hook runs this same skill in a headless Sonnet session when the
gates open, so these instructions have to work unattended. Do the work, then
report compactly.

## Paths

```bash
echo "$HOME/.claude/projects/$(pwd | sed 's|/|-|g')"
```

That directory holds this project's session transcripts — large JSONL files, to
be grepped narrowly and never read whole. Memory lives in its `memory/`
subdirectory, which already exists.

**Only write inside the memory directory.** A dream never modifies project code,
config, or anything else in the working tree.

## Phase 1 — Orient

1. `ls` the memory directory to see what already exists
2. Read `MEMORY.md` to understand the current index; note if over 150 lines
3. Skim existing topic files (first ~30 lines of each) to gauge coverage and
   freshness, so you improve them rather than creating duplicates
4. If `logs/` or `sessions/` subdirectories exist (assistant-mode layout), list
   them and review the most recent entries

## Phase 2 — Gather recent signal

Look for new information worth persisting. Sources in priority order:

1. **Daily logs** — `logs/YYYY/MM/YYYY-MM-DD.md` if present. This is the
   append-only stream and the richest source; read the entries added since the
   last consolidation.
2. **Existing memories that drifted** — facts that contradict what the codebase
   or git history shows now.
3. **Transcript search** — only when you need a specific detail you already
   suspect matters (e.g. "what was the error from yesterday's build failure?").
   Grep narrow terms:

   ```bash
   grep -rn "<narrow term>" <transcript-dir> --include="*.jsonl" | tail -50
   ```

Do not exhaustively read transcripts. Look only for things you already suspect
matter.

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

- **Persist new signal from Phase 2** as new memory files, or by merging it into
  the existing topic file it belongs to. Prefer merging — a near-duplicate is
  worse than a longer file.
- **Use the format and type conventions below.** That section is the source of
  truth for what to save, how to structure the frontmatter, and what NOT to save.
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

## Memory file format

Each memory is ONE file holding ONE fact, with frontmatter:

```markdown
---
name: <short-kebab-case-slug>
description: <one-line summary - used to decide relevance during recall>
metadata:
  type: user | feedback | project | reference
---

<the fact; for feedback/project, follow with **Why:** and **How to apply:** lines.
 Link related memories with [[their-name]].>
```

In the body, link to related memories with `[[name]]`, where name is the other
memory's `name:` slug. Link liberally — a `[[name]]` that does not match an
existing memory yet is fine; it marks something worth writing later, not an
error.

Types:

- `user` — who the user is (role, expertise, preferences)
- `feedback` — guidance the user has given on how to work, both corrections and
  confirmed approaches; include the why
- `project` — ongoing work, goals, or constraints not derivable from the code or
  git history; convert relative dates to absolute
- `reference` — pointers to external resources (URLs, dashboards, tickets)

Before saving, check for an existing file that already covers it — update that
file rather than creating a duplicate; delete memories that turn out to be wrong.
Do NOT save what the repo already records (code structure, past fixes, git
history, CLAUDE.md) or what only matters to a single conversation.

## Rules

- Do NOT create memories about the current task or conversation — a dream
  consolidates past sessions, it does not journal this one
- Do NOT read full JSONL transcripts — grep narrowly for specific terms only
- If everything is already tight and nothing changed, say "Memory is clean — no
  changes needed" and stop
- Report in a few plain-text lines: files created, merged, updated, deleted, and
  index lines changed. No preamble, no restating the phases, no dumping file
  contents.
