#!/usr/bin/env bash
# Self-check for gate-check.sh. Run: bash scripts/test-gate-check.sh
# Uses a fake $HOME so it never touches real state or memories.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/gate-check.sh"
SEGMENT="$(cd "$(dirname "$0")" && pwd)/dream-segment.sh"
FAILED=0

check() { # check <label> <expected: fire|quiet> <actual output>
  local label="$1" expect="$2" out="$3" got
  if [ -n "$out" ]; then got=fire; else got=quiet; fi
  if [ "$got" = "$expect" ]; then
    echo "ok   — $label"
  else
    echo "FAIL — $label (expected $expect, got $got)"
    FAILED=1
  fi
}

# Build a sandbox: project dir with N transcripts and a memory dir.
setup() { # setup <n_transcripts> <with_memory_dir>
  SANDBOX="$(mktemp -d)"
  PROJ="$SANDBOX/.claude/projects/-fake-proj"
  STATE="$SANDBOX/.claude/dream-plugin-state/-fake-proj"   # per-project, not global
  mkdir -p "$PROJ"
  [ "$2" = yes ] && mkdir -p "$PROJ/memory"
  local i
  for ((i = 0; i < $1; i++)); do : > "$PROJ/session-$i.jsonl"; done
}

run() { # run <stdin payload> — echoes hook output, empty if gates closed
  HOME="$SANDBOX" bash "$SCRIPT" <<<"$1" 2>/dev/null
}

payload='{"hook_event_name":"SessionStart","transcript_path":"PROJ/session-0.jsonl","cwd":"/fake/proj"}'

# 1. No memory directory → still fires, and creates the dir for the dreamer.
setup 10 no
check "no memory dir still fires" fire "$(run "${payload/PROJ/$PROJ}")"
check "no memory dir gets created" fire "$([ -d "$PROJ/memory" ] && echo yes)"

# 2. All gates open (no lock file = never consolidated, 10 sessions).
setup 10 yes
check "cold start with 10 sessions fires" fire "$(run "${payload/PROJ/$PROJ}")"

# 3. Too few sessions.
setup 2 yes
check "2 sessions stays quiet" quiet "$(run "${payload/PROJ/$PROJ}")"

# 4. Time gate closed — lock file is fresh.
setup 10 yes
mkdir -p "$STATE"
touch "$STATE/.consolidate-lock"
check "fresh lock stays quiet" quiet "$(run "${payload/PROJ/$PROJ}")"

# 5. Cooldown gate — old lock, but nagged just now.
setup 10 yes
mkdir -p "$STATE"
touch -t 202001010000 "$STATE/.consolidate-lock"
touch "$STATE/.last-nag"
check "recent nag stays quiet" quiet "$(run "${payload/PROJ/$PROJ}")"

# 6. Sessions are only counted if newer than the lock.
setup 10 yes
mkdir -p "$STATE"
touch -t 202001010000 "$STATE/.consolidate-lock"
touch -t 201901010000 "$PROJ"/*.jsonl                            # all older than lock
check "transcripts older than lock don't count" quiet "$(run "${payload/PROJ/$PROJ}")"

# 7. Fallback path: no transcript_path, cwd slugified instead.
setup 10 yes
mv "$SANDBOX/.claude/projects/-fake-proj" "$SANDBOX/.claude/projects/-fake-cwd"
check "cwd fallback resolves project dir" fire \
  "$(run '{"hook_event_name":"SessionStart","cwd":"/fake/cwd"}')"

# 8. Empty stdin must not crash (set -e + unbound-safe).
setup 10 yes
check "empty stdin does not crash" quiet "$(HOME="$SANDBOX" bash "$SCRIPT" </dev/null 2>&1)"

# --- Status line marker (.due) ---
# The segment script only tests for the marker, so what matters is that
# gate-check.sh writes it exactly when consolidation is due and clears it
# otherwise — including on the cooldown path, where the injection is
# suppressed but the dream is still owed.

due() { [ -f "$STATE/.due" ] && echo yes; }
# The segment slugifies the launch directory it is given; /fake/proj → -fake-proj.
segment() { HOME="$SANDBOX" bash "$SEGMENT" /fake/proj; }

# 9. Gates open → marker written, segment speaks.
setup 10 yes
run "${payload/PROJ/$PROJ}" >/dev/null
check "due marker written when gates open" fire "$(due)"
check "segment renders when due" fire "$(segment)"

# 10. Cooldown suppresses the nag but the dream is still owed — marker stays.
setup 10 yes
mkdir -p "$STATE"
touch -t 202001010000 "$STATE/.consolidate-lock"
touch "$STATE/.last-nag"
run "${payload/PROJ/$PROJ}" >/dev/null
check "due marker survives cooldown" fire "$(due)"

# 11. A stale marker is cleared once the lock is fresh again — this is what
#     stops the status line nagging forever after a consolidation.
setup 10 yes
mkdir -p "$STATE"
touch "$STATE/.due"
touch "$STATE/.consolidate-lock"
run "${payload/PROJ/$PROJ}" >/dev/null
check "fresh lock clears stale due marker" quiet "$(due)"
check "segment silent when not due" quiet "$(segment)"

# 12. Too few sessions also clears it.
setup 2 yes
mkdir -p "$STATE"
touch "$STATE/.due"
touch -t 202001010000 "$STATE/.consolidate-lock"
run "${payload/PROJ/$PROJ}" >/dev/null
check "session gate clears stale due marker" quiet "$(due)"

# --- Per-project isolation ---
# Gates are keyed by project slug because memories are per-project. A global lock
# meant dreaming in one project silenced every other one for MIN_HOURS, and the
# first project opened after the window consumed it for all of them.

# 13. A fresh consolidation in project A must not close project B's gates.
setup 10 yes
OTHER="$SANDBOX/.claude/projects/-other-proj"
mkdir -p "$OTHER/memory"
for i in 0 1 2 3 4 5 6 7 8 9; do : > "$OTHER/session-$i.jsonl"; done
mkdir -p "$SANDBOX/.claude/dream-plugin-state/-other-proj"
touch "$SANDBOX/.claude/dream-plugin-state/-other-proj/.consolidate-lock"
check "another project's fresh lock does not gate this one" fire \
  "$(run "${payload/PROJ/$PROJ}")"

# 14. ...and the converse: this project's own fresh lock still gates it, so the
#     isolation above is real rather than the lock being ignored entirely.
mkdir -p "$STATE"
touch "$STATE/.consolidate-lock"
check "own fresh lock still gates" quiet "$(run "${payload/PROJ/$PROJ}")"

# 15. Marker files are per-project too — project A's .due must not light up the
#     segment for project B.
setup 10 yes
mkdir -p "$SANDBOX/.claude/dream-plugin-state/-other-proj"
touch "$SANDBOX/.claude/dream-plugin-state/-other-proj/.due"
check "segment ignores another project's due marker" quiet \
  "$(HOME="$SANDBOX" bash "$SEGMENT" /fake/proj)"

# 16. Nothing is ever written to the old global path. Tests 13 and 15 state the
#     cross-project contract but cannot detect a regression to global state —
#     under a global implementation the per-project files they seed are simply
#     never read, so they still pass. This one fails the moment state moves back.
setup 10 yes
run "${payload/PROJ/$PROJ}" >/dev/null
check "no state written to the global path" quiet \
  "$(ls -A "$SANDBOX/.claude/dream-plugin-state/" 2>/dev/null | grep -v '^-fake-proj$')"

# 17. An empty memory directory is not a gate — a project with zero memories is
#     precisely the one that needs a first consolidation to generate some.
setup 10 yes
check "empty memory dir fires" fire "$(run "${payload/PROJ/$PROJ}")"

# --- The session gate must count the session it is running in ---
# SessionStart fires *before* Claude Code creates this session's transcript, so
# the file named by transcript_path does not exist yet. Counting only what is on
# disk therefore dropped the current session and the nag arrived a session late:
# at MIN_SESSIONS-1 the hook stayed quiet, and by the time the status command was
# run mid-session the same find saw one more file and reported the gate OPEN.
#
# Every payload above names a transcript that setup() created, which is why the
# suite never caught this. This payload names one it did not.
payload_new='{"hook_event_name":"SessionStart","transcript_path":"PROJ/session-new.jsonl","cwd":"/fake/proj"}'

# 18. MIN_SESSIONS-1 on disk plus the session being started reaches the threshold.
setup 4 yes
check "current session counts toward the session gate" fire \
  "$(run "${payload_new/PROJ/$PROJ}")"

# 19. ...and it is worth exactly one session, not a free pass through the gate.
setup 3 yes
check "current session is worth one, not more" quiet \
  "$(run "${payload_new/PROJ/$PROJ}")"

# 20. A resumed or compacted session already has its transcript on disk, so it is
#     in the find count already. Adding it again would fire the nag a session
#     early — the bump has to be conditional on the file's absence.
setup 4 yes
check "transcript already on disk is not counted twice" quiet \
  "$(run "${payload/PROJ/$PROJ}")"

exit "$FAILED"
