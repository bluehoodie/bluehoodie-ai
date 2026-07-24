#!/usr/bin/env bash
# Dream gate check — called by SessionStart hook.
# Checks time + session gates. Outputs JSON with additionalContext if dream is due.
#
# Gate order (cheapest first):
#   1. Time: hours since last consolidation >= MIN_HOURS
#   2. Sessions: transcript count with mtime > last consolidation >= MIN_SESSIONS
#   3. Cooldown: don't nag more than once per COOLDOWN_HOURS
#
# Hook input arrives as JSON on stdin (transcript_path, cwd, ...) and that is how
# the project directory is resolved. Never derive it from the git root: Claude Code
# slugifies the launch cwd, so a session started in a subdirectory of a repo gets
# its own project directory.
#
# Environment:
#   DREAM_MIN_HOURS    — minimum hours between consolidations (default: 24)
#   DREAM_MIN_SESSIONS — minimum new sessions required (default: 5)
#   DREAM_COOLDOWN_HOURS — hours between nag injections (default: 8)

set -euo pipefail

MIN_HOURS="${DREAM_MIN_HOURS:-24}"
MIN_SESSIONS="${DREAM_MIN_SESSIONS:-5}"
COOLDOWN_HOURS="${DREAM_COOLDOWN_HOURS:-8}"

INPUT="$(cat 2>/dev/null || true)"

# Pull a top-level string field out of the hook payload. These values are paths —
# no embedded quotes or escapes — so this is enough, and avoids a jq dependency.
json_field() {
  printf '%s' "$INPUT" |
    sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

# Resolve the project transcript directory. Preferred source is transcript_path
# from the hook payload — that file lives in the directory we want. Fall back to
# slugifying cwd the way Claude Code does (every "/" becomes "-").
resolve_project_dir() {
  local transcript_path cwd
  transcript_path="$(json_field transcript_path)"
  if [ -n "$transcript_path" ]; then
    dirname "$transcript_path"
    return
  fi
  cwd="$(json_field cwd)"
  cwd="${cwd:-$PWD}"
  printf '%s/.claude/projects/%s\n' "$HOME" "$(printf '%s' "$cwd" | sed 's|/|-|g')"
}

mtime() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    stat -f %m "$1" 2>/dev/null || echo 0
  else
    stat -c %Y "$1" 2>/dev/null || echo 0
  fi
}

PROJECT_DIR="$(resolve_project_dir)"
MEM_DIR="$PROJECT_DIR/memory"

# No memory directory / an empty one is NOT a gate: that is a project that has
# never dreamed, which is exactly when the first consolidation should run. Create
# it so the dreamer has somewhere to write (the agent deliberately does not mkdir).
mkdir -p "$MEM_DIR"

# State is per-project, keyed by the same slug Claude Code uses for the transcript
# directory. Memories are per-project, so the gates must be too: a global lock let
# a dream in one project silence every other project for MIN_HOURS, and whichever
# project you happened to open first consumed the window for all of them.
DREAM_STATE_DIR="$HOME/.claude/dream-plugin-state/$(basename "$PROJECT_DIR")"
mkdir -p "$DREAM_STATE_DIR"

LOCK_FILE="$DREAM_STATE_DIR/.consolidate-lock"
NAG_FILE="$DREAM_STATE_DIR/.last-nag"
# Marker read by dream-segment.sh. The status line re-runs on a 300ms debounce and
# cannot afford the session gate's find, so the verdict is written here instead.
DUE_FILE="$DREAM_STATE_DIR/.due"

# --- Gate 1: Time ---
last_consolidated=0
[ -f "$LOCK_FILE" ] && last_consolidated=$(mtime "$LOCK_FILE")

now=$(date +%s)
hours_since=$(( (now - last_consolidated) / 3600 ))

if [ "$hours_since" -lt "$MIN_HOURS" ]; then
  rm -f "$DUE_FILE"
  exit 0
fi

# --- Gate 2: Sessions ---
session_count=0
if [ -f "$LOCK_FILE" ]; then
  session_count=$(find "$PROJECT_DIR" -maxdepth 1 -name "*.jsonl" -newer "$LOCK_FILE" 2>/dev/null | wc -l | tr -d ' ')
else
  session_count=$(find "$PROJECT_DIR" -maxdepth 1 -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
fi

if [ "$session_count" -lt "$MIN_SESSIONS" ]; then
  rm -f "$DUE_FILE"
  exit 0
fi

# Past this point consolidation IS due. The cooldown below only suppresses the
# context injection, so the marker is written before it — a quiet session still
# shows "dream due" in the status line.
touch "$DUE_FILE"

# --- Cooldown: Don't nag too often ---
last_nag=0
[ -f "$NAG_FILE" ] && last_nag=$(mtime "$NAG_FILE")
nag_hours_since=$(( (now - last_nag) / 3600 ))

if [ "$nag_hours_since" -lt "$COOLDOWN_HOURS" ]; then
  exit 0
fi

# --- All gates passed ---
# Update nag timestamp
touch "$NAG_FILE"

if [ "$last_consolidated" -eq 0 ]; then
  age="no prior consolidation"
else
  age="${hours_since}h since last consolidation (threshold: ${MIN_HOURS}h)"
fi

# Output structured hook response
cat <<HOOK_JSON
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Memory consolidation is due: ${age}, ${session_count} new sessions (threshold: ${MIN_SESSIONS}). Use the dream:dream skill to consolidate after handling the user's request. Memory directory: ${MEM_DIR} — session transcripts: ${PROJECT_DIR}"
  }
}
HOOK_JSON
