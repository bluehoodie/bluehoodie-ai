# Dream

Periodic memory consolidation for [Claude Code](https://code.claude.com/docs/en/overview). Reviews, deduplicates, prunes, and reindexes Claude Code's file-based memory system so it stays useful instead of accumulating drift — and writes down recent signal that never made it into a memory.

## The Problem

Claude Code's auto-memory saves context across sessions into `~/.claude/projects/<project>/memory/`, where `<project>` is the launch directory with every `/` replaced by `-`. Over time this suffers from **drift** (facts go stale), **duplication** (sessions record overlapping information), **bloat** (MEMORY.md outgrows its usefulness), **date rot** ("last week" loses meaning), and **missing signal** (discoveries worth keeping never get written down).

Dream fixes this with a four-phase pass — orient, gather, consolidate, prune — run automatically or on demand.

## Install

```
/plugin marketplace add bluehoodie/bluehoodie-ai
/plugin install dream@bluehoodie-ai
```

## Usage

| Command | What it does |
|---------|-------------|
| `/dream:dream` | Consolidate now |
| `/dream:dream-status` | Gate state, last run, memory stats |
| `/dream:dream-restore` | Undo the last dream from its snapshot |
| `/dream:dream-reset` | Clear state so the gates reopen |

Asking in plain language — "dream", "consolidate my memory files" — invokes the same skill.

## How it works

```
Session starts
  └─> SessionStart hook (async) runs `dream.py gate`
       ├─ Time gate:    < MIN_HOURS since last run  → exit
       ├─ Session gate: < MIN_SESSIONS new transcripts → exit
       └─ both open → stamp the lock, launch `claude -p "/dream:dream"`
                      (detached, Sonnet, DREAM_CHILD=1, log to last-run.log)
```

The gates live in the hook rather than in the launched session because spinning up that session is the cost they exist to avoid — a closed gate has to be a cheap process exit, not a model call. The hook is `async`, so it never blocks session start.

An open gate **launches** the consolidation rather than suggesting one. Injected context is advisory, and a deferred instruction competes with whatever you actually asked for; across the 25 sessions where the old "consolidation is due" notice fired, it was acted on zero times.

The automatic and manual paths are the same path: both invoke `/dream:dream`. The launched session runs it headlessly against the project directory it was launched from, so it resolves exactly the paths you would.

The lock is stamped **at launch**, not when the consolidation finishes. Closing the time gate has to be a deterministic write — when it depended on the dreamer remembering to run a `touch`, a run that forgot left every later session launching another dream. The cost is that a crashed dream waits `MIN_HOURS` rather than retrying sooner, which is the right trade for a maintenance job.

`DREAM_CHILD=1` on the launched session makes its own `gate` a no-op. It is Claude Code, so it fires SessionStart too, and without the guard that recurses without bound.

Having no memories yet is not a gate — a missing or empty `memory/` directory is the state of a project that has never dreamed, precisely the one whose first consolidation has memories to generate. The launch creates the directory.

The launch snapshots `memory/` into the state directory before the dream starts. A dream rewrites memory in place and that directory is under no version control, so a bad merge or an over-eager prune would otherwise be unrecoverable — `/dream:dream-restore` puts the snapshot back. There is one snapshot per project, replaced (not merged into) on every launch: merging would resurrect files an earlier dream deleted on purpose. Restoring discards everything written since the dream launched, including memories saved afterwards, and `/dream:dream-reset` deletes the snapshot along with the rest of the state.

The session count includes the session being started. SessionStart fires before Claude Code writes that session's transcript, so counting only what is on disk would open the gate a session late.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `DREAM_MIN_HOURS` | `24` | Hours between consolidations |
| `DREAM_MIN_SESSIONS` | `5` | New sessions needed to trigger |
| `DREAM_CLAUDE_BIN` | `claude` | Executable used to launch the dream |

## State

`~/.claude/dream-plugin-state/<project-slug>/`, keyed by the same slug Claude Code uses for the transcript directory. Memories are per-project, so the gates are too — consolidating one project never silences another.

| File | Purpose |
|------|---------|
| `.consolidate-lock` | mtime = last launch; drives both gates |
| `memory-backup/` | copy of `memory/` as it stood when the last dream launched |
| `last-run.log` | output of the most recent dream |

## Project structure

```
plugins/dream/
├── .claude-plugin/plugin.json   # manifest
├── hooks/hooks.json             # SessionStart → dream.py gate (async)
├── scripts/dream.py             # gate | run | status | restore | reset
├── scripts/test_dream.py        # self-check
├── skills/dream/SKILL.md        # the four-phase consolidation — the only copy
├── commands/dream-status.md
├── commands/dream-restore.md
└── commands/dream-reset.md
```

Run `python3 scripts/test_dream.py` for the self-check. It uses a sandbox `$HOME` and a stub `claude`, so it never touches real state, real memories, or spawns a real session.

## Background

Claude Code has a built-in dream feature behind feature flags. This plugin reproduces its published four-phase consolidation prompt using the public plugin API — a hook that evaluates the gates and launches the work, and a skill holding the prompt. The consolidation is pinned to Sonnet and runs in its own detached session, keeping it off an expensive session model and out of your context window. It needs no feature flags.

Model and tools are set on the launch in `dream.py`. Haiku is not recommended — staleness checking and merge-vs-dedupe are judgment calls.

## License

MIT
