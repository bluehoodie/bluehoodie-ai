#!/usr/bin/env bash
# Self-check for gate-check.sh. Run: bash scripts/test-gate-check.sh
# Uses a fake $HOME so it never touches real state or memories.

set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/gate-check.sh"
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
  mkdir -p "$PROJ"
  [ "$2" = yes ] && mkdir -p "$PROJ/memory"
  local i
  for ((i = 0; i < $1; i++)); do : > "$PROJ/session-$i.jsonl"; done
}

run() { # run <stdin payload> — echoes hook output, empty if gates closed
  HOME="$SANDBOX" bash "$SCRIPT" <<<"$1" 2>/dev/null
}

payload='{"hook_event_name":"SessionStart","transcript_path":"PROJ/session-0.jsonl","cwd":"/fake/proj"}'

# 1. No memory directory → never fires, no matter how many sessions.
setup 10 no
check "no memory dir stays quiet" quiet "$(run "${payload/PROJ/$PROJ}")"

# 2. All gates open (no lock file = never consolidated, 10 sessions).
setup 10 yes
check "cold start with 10 sessions fires" fire "$(run "${payload/PROJ/$PROJ}")"

# 3. Too few sessions.
setup 2 yes
check "2 sessions stays quiet" quiet "$(run "${payload/PROJ/$PROJ}")"

# 4. Time gate closed — lock file is fresh.
setup 10 yes
mkdir -p "$SANDBOX/.claude/dream-plugin-state"
touch "$SANDBOX/.claude/dream-plugin-state/.consolidate-lock"
check "fresh lock stays quiet" quiet "$(run "${payload/PROJ/$PROJ}")"

# 5. Cooldown gate — old lock, but nagged just now.
setup 10 yes
mkdir -p "$SANDBOX/.claude/dream-plugin-state"
touch -t 202001010000 "$SANDBOX/.claude/dream-plugin-state/.consolidate-lock"
touch "$SANDBOX/.claude/dream-plugin-state/.last-nag"
check "recent nag stays quiet" quiet "$(run "${payload/PROJ/$PROJ}")"

# 6. Sessions are only counted if newer than the lock.
setup 10 yes
mkdir -p "$SANDBOX/.claude/dream-plugin-state"
touch "$SANDBOX/.claude/dream-plugin-state/.consolidate-lock"   # newer than transcripts
touch -t 202001010000 "$SANDBOX/.claude/dream-plugin-state/.consolidate-lock"
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

exit "$FAILED"
