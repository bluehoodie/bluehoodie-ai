#!/usr/bin/env python3
"""Dream — periodic memory consolidation for Claude Code.

Verbs:
  gate    SessionStart hook. Reads the hook payload on stdin and launches a
          consolidation when the time and session gates are both open.
  run     Launch one now, ignoring the gates.
  status  Print the gate state.
  reset   Clear this project's state so the gates reopen.

The gates live here rather than in the launched session because spinning up that
session is the cost they exist to avoid: a closed gate has to be a cheap process
exit, not a model call.

State lives in ~/.claude/dream-plugin-state/<project-slug>/, keyed by the same
slug Claude Code uses for the transcript directory. Memories are per-project, so
the gates are too — consolidating one project must not silence another.

Environment:
  DREAM_MIN_HOURS     hours between consolidations (default: 24)
  DREAM_MIN_SESSIONS  new sessions required (default: 5)
  DREAM_CLAUDE_BIN    claude executable to launch (default: claude)
  DREAM_CHILD         set on the launched session; makes `gate` a no-op, so a
                      dream can never start another dream
"""

import json
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

MIN_HOURS = float(os.environ.get("DREAM_MIN_HOURS") or 24)
MIN_SESSIONS = int(os.environ.get("DREAM_MIN_SESSIONS") or 5)
CLAUDE_BIN = os.environ.get("DREAM_CLAUDE_BIN") or "claude"

# The launched session invokes the same skill you would type. One entry point,
# so the automatic and manual dreams cannot drift apart.
PROMPT = "/dream:dream"


def resolve(payload):
    """Return (transcript directory, launch directory) for this session."""
    cwd = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    transcript = payload.get("transcript_path")
    # transcript_path is authoritative when present — it lives in the directory we
    # want. Otherwise slugify the launch cwd the way Claude Code does. Never use
    # the git root: a session started in a subdirectory of a repo is its own
    # project as far as Claude Code is concerned.
    if transcript:
        return Path(transcript).parent, cwd
    return Path.home() / ".claude" / "projects" / cwd.replace("/", "-"), cwd


def state_dir(project):
    return Path.home() / ".claude" / "dream-plugin-state" / project.name


def mtime(path):
    return path.stat().st_mtime if path.exists() else 0


def gates(project, current_session=0):
    """Return (hours since last consolidation, new sessions since it)."""
    last = mtime(state_dir(project) / ".consolidate-lock")
    hours = (time.time() - last) / 3600 if last else float("inf")
    sessions = sum(1 for f in project.glob("*.jsonl") if f.stat().st_mtime > last)
    return hours, sessions + current_session


def launch(project, cwd):
    (project / "memory").mkdir(parents=True, exist_ok=True)
    state = state_dir(project)
    state.mkdir(parents=True, exist_ok=True)

    # Stamp the lock at launch, not when the consolidation finishes. Closing the
    # time gate has to be a deterministic write; when it depended on the dreamer
    # remembering to run a `touch`, a run that forgot left every later session
    # launching another dream.
    (state / ".consolidate-lock").touch()

    if not shutil.which(CLAUDE_BIN):
        return
    with open(state / "last-run.log", "w") as log:
        subprocess.Popen(
            [CLAUDE_BIN, "-p", PROMPT, "--model", "sonnet",
             "--allowedTools", "Read,Write,Edit,Glob,Grep,Bash"],
            cwd=cwd if os.path.isdir(cwd) else None,
            env={**os.environ, "DREAM_CHILD": "1"},
            stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
            start_new_session=True,  # outlives the hook
        )


def gate():
    # The dream runs Claude Code, which fires SessionStart, which runs this. Without
    # the guard that is an unbounded fork bomb of dreams.
    if os.environ.get("DREAM_CHILD"):
        return
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except (ValueError, OSError):
        payload = {}
    project, cwd = resolve(payload)

    # SessionStart fires before Claude Code writes this session's transcript, so
    # the file named by transcript_path is not on disk yet. Count it anyway or the
    # gate opens a session late. A resumed or compacted session reuses an existing
    # transcript, which the glob already saw — hence the existence check.
    transcript = payload.get("transcript_path")
    current = 0 if transcript and os.path.exists(transcript) else 1

    hours, sessions = gates(project, current)
    if hours >= MIN_HOURS and sessions >= MIN_SESSIONS:
        launch(project, cwd)


def run():
    launch(*resolve({}))


def status():
    project, _ = resolve({})
    last = mtime(state_dir(project) / ".consolidate-lock")
    hours, sessions = gates(project)

    when = datetime.fromtimestamp(last).strftime("%Y-%m-%d %H:%M") if last else "never"
    age = " (%.0fh ago)" % hours if last else ""
    time_gate = "OPEN" if hours >= MIN_HOURS else "CLOSED (%.0fh to go)" % (MIN_HOURS - hours)
    sess_gate = "OPEN" if sessions >= MIN_SESSIONS else "CLOSED (%d to go)" % (MIN_SESSIONS - sessions)

    memory = project / "memory"
    files = list(memory.glob("*.md")) if memory.is_dir() else []
    index = memory / "MEMORY.md"
    lines = len(index.read_text().splitlines()) if index.exists() else 0

    print("Dream — %s" % project.name)
    print("  last run      %s%s" % (when, age))
    print("  time gate     %s  (>= %gh)" % (time_gate, MIN_HOURS))
    print("  sessions      %d since last run" % sessions)
    print("  session gate  %s  (>= %d)" % (sess_gate, MIN_SESSIONS))
    print("  memory        %d files%s" % (len(files), ", MEMORY.md %d lines" % lines if lines else ""))


def reset():
    project, _ = resolve({})
    shutil.rmtree(state_dir(project), ignore_errors=True)
    print("Dream state reset for %s. The gates reopen on the next session." % project.name)


VERBS = {"gate": gate, "run": run, "status": status, "reset": reset}

if __name__ == "__main__":
    verb = sys.argv[1] if len(sys.argv) > 1 else "status"
    if verb not in VERBS:
        sys.exit("dream.py: unknown verb %r (%s)" % (verb, "|".join(VERBS)))
    VERBS[verb]()
