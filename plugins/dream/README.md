# Dream

Periodic memory consolidation for [Claude Code](https://code.claude.com/docs/en/overview). Reviews, deduplicates, prunes, and reindexes Claude Code's file-based memory system so it stays useful instead of accumulating drift — and writes down recent signal that never made it into a memory.

## The Problem

Claude Code's auto-memory saves context across sessions into `~/.claude/projects/<project>/memory/`, where `<project>` is the launch directory with every `/` replaced by `-`. Over time this system suffers from:

- **Drift** — facts go stale as the codebase evolves
- **Duplication** — multiple sessions record overlapping information
- **Bloat** — MEMORY.md grows past its useful size
- **Date rot** — relative dates ("last week") lose meaning
- **Missing signal** — discoveries worth keeping never get written down at all

Dream fixes this by running a 4-phase consolidation pass — orient, gather, consolidate, prune — either automatically or on demand.

## Install

```
/plugin marketplace add bluehoodie/bluehoodie-ai
/plugin install dream@bluehoodie-ai
```

## Usage

### Commands

Plugin skills are namespaced, so the invocation names carry the `dream:` prefix:

| Command | What it does |
|---------|-------------|
| `/dream:dream` | Run consolidation now |
| `/dream:dream-status` | Show gate status, last run time, memory stats |
| `/dream:dream-reset` | Clear state so gates reopen immediately |

Asking for it in plain language — "dream", "consolidate my memory files" — invokes the same skill.

### Auto-trigger

A **SessionStart hook** checks three gates:

| Gate | Default | What it checks |
|------|---------|---------------|
| Time | 24h | Hours since last consolidation |
| Sessions | 5 | New session transcripts since last run, counting the one starting |
| Cooldown | 8h | Prevents repeated launches within a window |

When all gates pass the hook **launches the dream itself**, as a detached headless `claude -p` session running the `dreamer` prompt against this project's memory directory. Your session is told a consolidation started and otherwise carries on; the dream writes memories, stamps the lock, and exits on its own. Output lands in `last-run.log` in the project's state directory.

It used to only inject "Memory consolidation is due, use the dream:dream skill" and leave the session to act on it. Injected context is advisory, and a deferred instruction competes with whatever you actually asked for: across the 25 sessions where that notice fired, it was acted on zero times. A gate that opens has to start something itself.

The launched session runs with `DREAM_CHILD=1`, which makes `gate-check.sh` a no-op — it is Claude Code, so it fires SessionStart too, and without the guard that recurses without bound. The cooldown gate is the failure backstop: the lock is stamped by the dreamer at the *end*, so a run that dies partway never closes the time gate, and only the cooldown stops every following session from launching another. If no `claude` is found on `PATH`, the hook falls back to the old advisory notice.

Having no memories yet is not a gate. A missing or empty `memory/` directory is the state of a project that has never dreamed — precisely the one whose first consolidation has memories to generate. The hook creates the directory if it is absent, since the `dreamer` agent deliberately does not.

The session count includes the session being started. SessionStart runs before Claude Code creates that session's transcript, so counting only the files on disk would open the gate a session late — and `dream-status.sh`, run mid-session once the file exists, would report the gate OPEN while the hook that had just run stayed quiet.

The gate script resolves the project directory from the `transcript_path` in the hook's stdin payload, falling back to slugifying the launch cwd. It does not use the git root — Claude Code keys projects off the directory you launched from, so a session started in a subdirectory of a repo has its own project directory.

The final phase of the consolidation stamps the lock file itself, resetting the time gate.

### Status line (opt-in)

The cooldown means a dream is owed for up to 8h before the hook launches one. For a visible reminder in the meantime, add one line to your own status line script:

```bash
bash ~/.claude/plugins/dream/scripts/dream-segment.sh
```

It prints `💤 dream due — run /dream:dream` when consolidation is owed, and nothing otherwise — so it costs you a row only when there's something to do. Remove the line to uninstall.

It reads the marker for the launch directory, defaulting to `$PWD`. If your sessions `cd` away from where Claude Code was launched, pass the directory explicitly:

```bash
bash ~/.claude/plugins/dream/scripts/dream-segment.sh "$(jq -r .workspace.project_dir <<<"$input")"
```

This is a snippet rather than a command that edits your settings because `settings.json` has exactly one `statusLine` slot, and it is probably already yours. A plugin cannot claim it: plugin `settings.json` supports only the `agent` and `subagentStatusLine` keys.

The segment does no work of its own — status lines re-run on a 300ms debounce, far too often for the session gate's `find`. `gate-check.sh` writes the verdict to a marker file at SessionStart and the segment is a single file test. The marker clears when the dream stamps the lock, so it goes quiet on its own once a consolidation lands.

### The 4-Phase Consolidation

1. **Orient** — list memory files, read MEMORY.md, skim topic files and any `logs/` or `sessions/` subdirectories
2. **Gather** — pull new signal from daily logs, drifted memories, and narrow transcript greps
3. **Audit & Consolidate** — check each memory for staleness, duplication, bloat, broken links, date rot; then write new memories, merge duplicates, fix stale facts, convert relative dates
4. **Prune & Index** — trim MEMORY.md to under 200 lines / 25KB, one-line entries, verify all links, stamp the lock

## Configuration

Set via environment variables in your shell profile:

| Variable | Default | Description |
|----------|---------|-------------|
| `DREAM_MIN_HOURS` | `24` | Hours between consolidations |
| `DREAM_MIN_SESSIONS` | `5` | New sessions needed to trigger |
| `DREAM_COOLDOWN_HOURS` | `8` | Hours between auto-launches |
| `DREAM_CLAUDE_BIN` | `claude` | Executable used to launch the headless dream |

## How It Works

```
Session starts
  └─> SessionStart hook fires gate-check.sh (project dir from stdin transcript_path)
       ├─ Memory dir:    mkdir -p memory/ (absent or empty is not a gate)
       ├─ Time gate:     stat lock file mtime, skip if < MIN_HOURS
       ├─ Session gate:  find transcripts newer than lock, +1 for this session,
       │                 skip if < MIN_SESSIONS
       ├─ Cooldown gate: stat nag file mtime, skip if < COOLDOWN_HOURS
       └─ All pass → launch detached `claude -p` running agents/dreamer.md
            │         (DREAM_CHILD=1 so its own hook is a no-op; log to state dir)
            ├─> hook returns immediately, your session is told a dream started
            └─> the detached dream, on its own:
                 ├─ Phase 1: Orient (read existing memories)
                 ├─ Phase 2: Gather (daily logs, narrow transcript greps)
                 ├─ Phase 3: Audit & Consolidate (write/merge/fix/delete)
                 ├─ Phase 4: Prune (trim MEMORY.md index) → stamp lock, clear .due
                 └─ summary written to last-run.log
```

`/dream:dream` still dispatches the `dreamer` subagent inside your session, for when you want to consolidate on demand and see the summary.

### State

State lives in `~/.claude/dream-plugin-state/<project-slug>/`, keyed by the same slug Claude Code uses for the transcript directory — memories are per-project, so the gates are too. Consolidating one project never silences another.

| File | Purpose |
|------|---------|
| `.consolidate-lock` | mtime = last consolidation timestamp |
| `.last-nag` | mtime = last auto-launch; caps launches to one per COOLDOWN_HOURS |
| `.due` | present = consolidation owed; read by the status line segment |
| `last-run.log` | output of the most recent auto-launched dream |

Every project the hook runs in gets a state directory once its time gate opens — including one with no memories yet, which is how a first consolidation ever gets triggered.

## Project Structure

```
plugins/dream/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── skills/dream/
│   └── SKILL.md                 # Dispatcher — resolves paths, calls the agent (/dream:dream)
├── agents/
│   └── dreamer.md               # 4-phase consolidation prompt, model-pinned
├── commands/
│   ├── dream-status.md          # /dream:dream-status
│   └── dream-reset.md           # /dream:dream-reset
├── hooks/
│   └── hooks.json               # SessionStart hook
├── scripts/
│   ├── gate-check.sh            # Gate evaluation logic
│   ├── dream-segment.sh         # Optional status line segment
│   ├── dream-status.sh          # Diagnostic output
│   └── test-gate-check.sh       # Gate + segment self-check
├── LICENSE
└── README.md
```

Run the gate logic self-check with `bash scripts/test-gate-check.sh` — it uses a sandboxed `$HOME`, so it never touches real state or memories.

## Background

Claude Code has a built-in dream feature, gated behind feature flags, that runs as a forked background subagent with its own task UI. This plugin reproduces its published four-phase consolidation prompt using the public plugin API — a hook that evaluates the gates and launches the work, an agent holding the consolidation prompt, and a skill for running it on demand. Either way the consolidation is pinned to Sonnet and runs off the critical path: auto-triggered it is a detached headless session, on demand it is a `background: true` subagent you track in `/tasks`. Both keep it off an expensive session model and out of the main context window. It needs no feature flags.

### Agent tuning

Both knobs live in the frontmatter of `agents/dreamer.md`:

| Field | Default | Note |
|-------|---------|------|
| `model` | `sonnet` | Haiku is not recommended — staleness checking and merge-vs-dedupe are judgment calls |
| `background` | `true` | Set `false` to make the session wait for the summary inline |

## License

MIT
