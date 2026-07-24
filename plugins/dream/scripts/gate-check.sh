#!/usr/bin/env bash
# Dream gate check — called by SessionStart hook.
# Checks time + session gates. When they all pass it LAUNCHES the dream, as a
# detached headless `claude -p` session, and reports that in additionalContext.
#
# It used to only inject "consolidation is due, use the dream:dream skill".
# Injected context is advisory: across the 25 sessions where that notice fired,
# it was acted on zero times. A gate that opens has to start something itself.
#
# Gate order (cheapest first):
#   1. Time: hours since last consolidation >= MIN_HOURS
#   2. Sessions: transcripts with mtime > last consolidation, plus the session
#      being started, >= MIN_SESSIONS
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
#   DREAM_COOLDOWN_HOURS — hours between dream launches (default: 8)
#   DREAM_CLAUDE_BIN   — claude executable to launch (default: claude)
#   DREAM_CHILD        — set by the launch below; makes this script a no-op so a
#                        dream session cannot start another dream session

set -euo pipefail

# The headless dream runs Claude Code, which fires SessionStart, which runs this
# script. Without this guard that is an unbounded fork bomb of dreams.
[ -n "${DREAM_CHILD:-}" ] && exit 0

MIN_HOURS="${DREAM_MIN_HOURS:-24}"
MIN_SESSIONS="${DREAM_MIN_SESSIONS:-5}"
COOLDOWN_HOURS="${DREAM_COOLDOWN_HOURS:-8}"
CLAUDE_BIN="${DREAM_CLAUDE_BIN:-claude}"
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

INPUT="$(cat 2>/dev/null || true)"

# Pull a top-level string field out of the hook payload. These values are paths —
# no embedded quotes or escapes — so this is enough, and avoids a jq dependency.
json_field() {
  printf '%s' "$INPUT" |
    sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

# This session's transcript. Note it does not exist yet at SessionStart — see the
# session gate below, which has to account for that.
TRANSCRIPT_PATH="$(json_field transcript_path)"

# Resolve the project transcript directory. Preferred source is transcript_path
# from the hook payload — that file lives in the directory we want. Fall back to
# slugifying cwd the way Claude Code does (every "/" becomes "-").
resolve_project_dir() {
  local cwd
  if [ -n "$TRANSCRIPT_PATH" ]; then
    dirname "$TRANSCRIPT_PATH"
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

# The find above cannot see the session we are starting: SessionStart runs before
# Claude Code creates its transcript. Count it anyway, or the gate opens a whole
# session late — and dream-status.sh, run mid-session once the file exists, reports
# OPEN while the hook that just ran said otherwise. Skip the bump when the file is
# already there (resume and compact reuse an existing transcript) so it counts once.
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -e "$TRANSCRIPT_PATH" ]; then
  session_count=$(( session_count + 1 ))
fi

if [ "$session_count" -lt "$MIN_SESSIONS" ]; then
  rm -f "$DUE_FILE"
  exit 0
fi

# Past this point consolidation IS due. The cooldown below only suppresses the
# context injection, so the marker is written before it — a quiet session still
# shows "dream due" in the status line.
touch "$DUE_FILE"

# --- Cooldown: Don't launch too often ---
# This is also the failure backstop. The lock is stamped by the dreamer when it
# finishes, so a run that dies partway never closes the time gate; without the
# cooldown every subsequent session would launch another one.
last_nag=0
[ -f "$NAG_FILE" ] && last_nag=$(mtime "$NAG_FILE")
nag_hours_since=$(( (now - last_nag) / 3600 ))

if [ "$nag_hours_since" -lt "$COOLDOWN_HOURS" ]; then
  exit 0
fi

# --- All gates passed: launch the dream ---
touch "$NAG_FILE"

if [ "$last_consolidated" -eq 0 ]; then
  age="no prior consolidation"
else
  age="${hours_since}h since last consolidation (threshold: ${MIN_HOURS}h)"
fi

# Detached so the 5s hook timeout is never in play, and so the dream outlives the
# hook. Tool access is scoped to what dreamer.md actually uses; it only ever
# writes inside the memory directory. Falls back to the old advisory notice when
# there is no claude on PATH — hook environments differ, and a silent no-op is
# the exact bug this replaces.
if command -v "$CLAUDE_BIN" >/dev/null 2>&1; then
  DREAM_CHILD=1 nohup "$CLAUDE_BIN" -p \
    "Read ${PLUGIN_ROOT}/agents/dreamer.md and follow it exactly. Memory directory: ${MEM_DIR}. Transcript directory: ${PROJECT_DIR}. Today's date: $(date +%F)." \
    --model sonnet \
    --allowedTools Read,Write,Edit,Glob,Grep,Bash \
    >"$DREAM_STATE_DIR/last-run.log" 2>&1 </dev/null &
  context="A background memory consolidation was launched for this project (${age}, ${session_count} new sessions). It runs in its own headless session — nothing to do here. Log: ${DREAM_STATE_DIR}/last-run.log"
else
  context="Memory consolidation is due: ${age}, ${session_count} new sessions (threshold: ${MIN_SESSIONS}). Use the dream:dream skill to consolidate after handling the user's request. Memory directory: ${MEM_DIR} — session transcripts: ${PROJECT_DIR}"
fi

# Output structured hook response
cat <<HOOK_JSON
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "${context}"
  }
}
HOOK_JSON
