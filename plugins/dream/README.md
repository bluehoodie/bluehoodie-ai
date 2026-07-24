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

A **SessionStart hook** skips silently if the project has no `memory/` directory, then checks three gates:

| Gate | Default | What it checks |
|------|---------|---------------|
| Time | 24h | Hours since last consolidation |
| Sessions | 5 | New session transcripts since last run |
| Cooldown | 8h | Prevents repeated prompts within a window |

When all gates pass, Claude sees a context injection: "Memory consolidation is due," carrying the exact memory and transcript paths. It handles your request first, then consolidates.

The gate script resolves the project directory from the `transcript_path` in the hook's stdin payload, falling back to slugifying the launch cwd. It does not use the git root — Claude Code keys projects off the directory you launched from, so a session started in a subdirectory of a repo has its own project directory.

The final phase of the consolidation stamps the lock file itself, resetting the time gate.

### Status line (opt-in)

The SessionStart notice fires once and scrolls away. For a persistent reminder, add one line to your own status line script:

```bash
bash ~/.claude/plugins/dream/scripts/dream-segment.sh
```

It prints `💤 dream due — run /dream:dream` when consolidation is owed, and nothing otherwise — so it costs you a row only when there's something to do. Remove the line to uninstall.

It reads the marker for the launch directory, defaulting to `$PWD`. If your sessions `cd` away from where Claude Code was launched, pass the directory explicitly:

```bash
bash ~/.claude/plugins/dream/scripts/dream-segment.sh "$(jq -r .workspace.project_dir <<<"$input")"
```

This is a snippet rather than a command that edits your settings because `settings.json` has exactly one `statusLine` slot, and it is probably already yours. A plugin cannot claim it: plugin `settings.json` supports only the `agent` and `subagentStatusLine` keys.

The segment does no work of its own — status lines re-run on a 300ms debounce, far too often for the session gate's `find`. `gate-check.sh` writes the verdict to a marker file at SessionStart and the segment is a single file test. A running consolidation needs no segment at all: the `dreamer` subagent shows up in `/tasks` on its own.

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
| `DREAM_COOLDOWN_HOURS` | `8` | Hours between auto-trigger prompts |

## How It Works

```
Session starts
  └─> SessionStart hook fires gate-check.sh (project dir from stdin transcript_path)
       ├─ Memory dir:    skip if this project has no memory/ directory
       ├─ Time gate:     stat lock file mtime, skip if < MIN_HOURS
       ├─ Session gate:  find transcripts newer than lock, skip if < MIN_SESSIONS  
       ├─ Cooldown gate: stat nag file mtime, skip if < COOLDOWN_HOURS
       └─ All pass → inject additionalContext into session
            └─> Claude runs dream:dream skill after user's request
                 └─> dispatches dream:dreamer subagent in background (paths + date)
                      ├─ Phase 1: Orient (read existing memories)
                      ├─ Phase 2: Gather (daily logs, narrow transcript greps)
                      ├─ Phase 3: Audit & Consolidate (write/merge/fix/delete)
                      ├─ Phase 4: Prune (trim MEMORY.md index) → stamp lock file
                      └─ returns a short summary → relayed to you
```

### State

State lives in `~/.claude/dream-plugin-state/<project-slug>/`, keyed by the same slug Claude Code uses for the transcript directory — memories are per-project, so the gates are too. Consolidating one project never silences another.

| File | Purpose |
|------|---------|
| `.consolidate-lock` | mtime = last consolidation timestamp |
| `.last-nag` | mtime = last auto-trigger prompt |
| `.due` | present = consolidation owed; read by the status line segment |

A project only gets a state directory once it has a `memory/` directory, so projects that never dream leave nothing behind.

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

Claude Code has a built-in dream feature, gated behind feature flags, that runs as a forked background subagent with its own task UI. This plugin reproduces its published four-phase consolidation prompt using the public plugin API — a hook for auto-triggering, a skill that dispatches the work, an agent holding the consolidation prompt, and shell scripts for gate evaluation. Consolidation runs in the plugin's `dreamer` subagent, declared `background: true` and pinned to Sonnet, so it stays off an expensive session model, out of the main context window, and off the critical path — you keep working while it runs, and track it in `/tasks`. It needs no feature flags.

### Agent tuning

Both knobs live in the frontmatter of `agents/dreamer.md`:

| Field | Default | Note |
|-------|---------|------|
| `model` | `sonnet` | Haiku is not recommended — staleness checking and merge-vs-dedupe are judgment calls |
| `background` | `true` | Set `false` to make the session wait for the summary inline |

## License

MIT
