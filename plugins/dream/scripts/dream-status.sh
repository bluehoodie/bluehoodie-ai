#!/usr/bin/env bash
# Print dream consolidation status — useful for debugging.
# Shows last consolidation time, sessions since, and gate status.

set -euo pipefail

MIN_HOURS="${DREAM_MIN_HOURS:-24}"
MIN_SESSIONS="${DREAM_MIN_SESSIONS:-5}"

# Claude Code slugifies the launch cwd, not the git root — a session started in a
# subdirectory of a repo gets its own project directory. State is keyed by the
# same slug, so each project's gates are independent.
slug="$(printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}" | sed 's|/|-|g')"
transcript_dir="$HOME/.claude/projects/${slug}"

DREAM_STATE_DIR="$HOME/.claude/dream-plugin-state/${slug}"
LOCK_FILE="$DREAM_STATE_DIR/.consolidate-lock"
NAG_FILE="$DREAM_STATE_DIR/.last-nag"

echo "=== Dream Plugin Status ==="
echo ""
echo "Project:             $slug"
echo ""

# Last consolidation
if [ -f "$LOCK_FILE" ]; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    last_ts=$(stat -f %m "$LOCK_FILE")
    last_date=$(date -r "$last_ts" "+%Y-%m-%d %H:%M:%S")
  else
    last_ts=$(stat -c %Y "$LOCK_FILE")
    last_date=$(date -d "@$last_ts" "+%Y-%m-%d %H:%M:%S")
  fi
  now=$(date +%s)
  hours_since=$(( (now - last_ts) / 3600 ))
  echo "Last consolidation:  $last_date ($hours_since hours ago)"
  if [ "$hours_since" -ge "$MIN_HOURS" ]; then
    echo "Time gate:           OPEN (>= ${MIN_HOURS}h)"
  else
    echo "Time gate:           CLOSED (need $(( MIN_HOURS - hours_since )) more hours)"
  fi
else
  echo "Last consolidation:  never"
  echo "Time gate:           OPEN (no prior consolidation)"
fi

echo ""

# Session count.
session_count=0
if [ -d "$transcript_dir" ]; then
  if [ -f "$LOCK_FILE" ]; then
    session_count=$(find "$transcript_dir" -maxdepth 1 -name "*.jsonl" -newer "$LOCK_FILE" 2>/dev/null | wc -l | tr -d ' ')
  else
    session_count=$(find "$transcript_dir" -maxdepth 1 -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
  fi
fi

echo "Sessions since last:  $session_count"
if [ "$session_count" -ge "$MIN_SESSIONS" ]; then
  echo "Session gate:         OPEN (>= ${MIN_SESSIONS})"
else
  echo "Session gate:         CLOSED (need $(( MIN_SESSIONS - session_count )) more)"
fi

echo ""

# Nag cooldown
if [ -f "$NAG_FILE" ]; then
  if [[ "$OSTYPE" == "darwin"* ]]; then
    nag_ts=$(stat -f %m "$NAG_FILE")
    nag_date=$(date -r "$nag_ts" "+%Y-%m-%d %H:%M:%S")
  else
    nag_ts=$(stat -c %Y "$NAG_FILE")
    nag_date=$(date -d "@$nag_ts" "+%Y-%m-%d %H:%M:%S")
  fi
  echo "Last nag:             $nag_date"
else
  echo "Last nag:             never"
fi

echo ""

# Memory directory
mem_dir="$transcript_dir/memory"
if [ -d "$mem_dir" ]; then
  file_count=$(find "$mem_dir" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  echo "Memory directory:     $mem_dir"
  echo "Memory files:         $file_count"
  if [ -f "$mem_dir/MEMORY.md" ]; then
    line_count=$(wc -l < "$mem_dir/MEMORY.md" | tr -d ' ')
    byte_count=$(wc -c < "$mem_dir/MEMORY.md" | tr -d ' ')
    echo "MEMORY.md:            $line_count lines, $byte_count bytes"
    if [ "$line_count" -gt 150 ]; then
      echo "                      WARNING: over 150 lines — consolidation recommended"
    fi
  fi
else
  echo "Memory directory:     not found"
fi
