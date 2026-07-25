#!/usr/bin/env python3
"""Self-check for dream.py. Run: python3 scripts/test_dream.py

Every test runs against a sandbox $HOME and a stub `claude`, so the suite never
touches real state, real memories, or spawns a real session.
"""

import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

DREAM = Path(__file__).resolve().parent / "dream.py"
FAILED = 0

STUB = """#!/usr/bin/env bash
{ printf '%s\\n' "$*"; printf 'DREAM_CHILD=%s\\n' "${DREAM_CHILD:-unset}"; pwd; } > "$LAUNCHED"
"""


def check(label, expected, actual):
    global FAILED
    if actual == expected:
        print(f"ok   — {label}")
    else:
        print(f"FAIL — {label} (expected {expected!r}, got {actual!r})")
        FAILED = 1


class Sandbox:
    """A fake $HOME holding one project with N session transcripts."""

    def __init__(self, sessions=0, memory=True):
        self.home = Path(tempfile.mkdtemp())
        self.work = self.home / "work"          # where the session was launched
        self.work.mkdir()
        self.slug = str(self.work).replace("/", "-")
        self.proj = self.home / ".claude" / "projects" / self.slug
        self.state = self.home / ".claude" / "dream-plugin-state" / self.slug
        self.proj.mkdir(parents=True)
        if memory:
            (self.proj / "memory").mkdir()
        for i in range(sessions):
            (self.proj / f"session-{i}.jsonl").touch()
        self.stub = self.home / "claude-stub"
        self.stub.write_text(STUB)
        self.stub.chmod(0o755)
        self.launched = self.home / "launched"

    def payload(self, transcript="session-0.jsonl"):
        d = {"hook_event_name": "SessionStart", "cwd": str(self.work)}
        if transcript:
            d["transcript_path"] = str(self.proj / transcript)
        return json.dumps(d)

    def run(self, *argv, stdin="", env=None):
        e = {
            **os.environ,
            "HOME": str(self.home),
            "DREAM_CLAUDE_BIN": str(self.stub),
            "LAUNCHED": str(self.launched),
            "CLAUDE_PROJECT_DIR": str(self.work),
        }
        e.update(env or {})
        return subprocess.run(
            [sys.executable, str(DREAM), *argv],
            input=stdin, capture_output=True, text=True, env=e, cwd=str(self.work),
        )

    def gate(self, transcript="session-0.jsonl", env=None):
        return self.run("gate", stdin=self.payload(transcript), env=env)

    def dreamed(self, wait=5.0):
        """Text the stub recorded, or '' if no dream was launched."""
        deadline = time.time() + wait
        while time.time() < deadline:
            if self.launched.exists():
                return self.launched.read_text()
            time.sleep(0.05)
        return ""

    def quiet(self):
        """No dream launched. Short wait — proving a negative, so keep it cheap."""
        return self.dreamed(wait=0.6) == ""

    def age_lock(self, mtime):
        self.state.mkdir(parents=True, exist_ok=True)
        lock = self.state / ".consolidate-lock"
        lock.touch()
        os.utime(lock, (mtime, mtime))
        return lock


DAY = 86400
LONG_AGO = time.time() - 400 * DAY


# --- Gates -----------------------------------------------------------------

s = Sandbox(sessions=10)
s.gate()
check("cold start with 10 sessions launches a dream", False, s.quiet())

s = Sandbox(sessions=2)
s.gate()
check("2 sessions stays quiet", True, s.quiet())

s = Sandbox(sessions=10)
s.age_lock(time.time())
s.gate()
check("fresh lock stays quiet", True, s.quiet())

s = Sandbox(sessions=10)
lock = s.age_lock(time.time() - 2 * DAY)
for f in s.proj.glob("*.jsonl"):
    os.utime(f, (LONG_AGO, LONG_AGO))
s.gate()
check("transcripts older than the lock are not counted", True, s.quiet())

s = Sandbox(sessions=10)
s.gate(transcript=None)
check("cwd fallback resolves the project dir", False, s.quiet())

s = Sandbox(sessions=10)
r = s.run("gate", stdin="")
check("empty stdin does not crash", 0, r.returncode)

s = Sandbox(sessions=10, memory=False)
s.gate()
check("a missing memory dir does not block the dream", False, s.quiet())
check("the launch creates the memory dir", True, (s.proj / "memory").is_dir())


# --- The session being started ---------------------------------------------
# SessionStart fires before Claude Code writes this session's transcript, so the
# file named by transcript_path does not exist yet. Counting only what is on disk
# opens the gate a session late.

s = Sandbox(sessions=4)
s.gate(transcript="session-new.jsonl")
check("the current session counts toward the session gate", False, s.quiet())

s = Sandbox(sessions=3)
s.gate(transcript="session-new.jsonl")
check("the current session is worth one, not a free pass", True, s.quiet())

s = Sandbox(sessions=4)
s.gate(transcript="session-0.jsonl")
check("a transcript already on disk is not counted twice", True, s.quiet())


# --- The lock is stamped by the launcher, not by the dreamer ----------------
# Stamping it at the end of the agent prompt made closing the time gate depend on
# a model remembering to run a `touch`. If it forgot, every later session launched
# another dream.

s = Sandbox(sessions=10)
s.gate()
s.dreamed()
check("the launch stamps the lock itself", True, (s.state / ".consolidate-lock").exists())

s.launched.unlink(missing_ok=True)
s.gate()
check("a stamped lock closes the gate for the next session", True, s.quiet())


# --- Per-project isolation --------------------------------------------------
# Memories are per-project, so the gates must be too: a global lock let a dream in
# one project silence every other project for MIN_HOURS.

s = Sandbox(sessions=10)
other = s.home / ".claude" / "dream-plugin-state" / "-other-proj"
other.mkdir(parents=True)
(other / ".consolidate-lock").touch()
s.gate()
check("another project's fresh lock does not gate this one", False, s.quiet())

s = Sandbox(sessions=10)
s.age_lock(time.time())
s.gate()
check("this project's own fresh lock still gates it", True, s.quiet())

s = Sandbox(sessions=10)
s.gate()
s.dreamed()
written = sorted(p.name for p in (s.home / ".claude" / "dream-plugin-state").iterdir())
check("no state is written outside this project's slug", [s.slug], written)


# --- The launch -------------------------------------------------------------

s = Sandbox(sessions=10)
s.gate()
launched = s.dreamed()
check("the dream runs headless", True, "-p " in launched)
check("the dream runs in the project's directory", True, str(s.work) in launched)
check("the child is marked DREAM_CHILD", True, "DREAM_CHILD=1" in launched)

s = Sandbox(sessions=10)
s.gate(env={"DREAM_CHILD": "1"})
check("a dream session never starts a dream", True, s.quiet())

s = Sandbox(sessions=2)
s.gate()
check("closed gates launch nothing", True, s.quiet())


# --- What the dream is told to mine -----------------------------------------
# The gate already knows which transcripts arrived since the last dream. Naming
# them turns "grep recent sessions" into a bounded instruction.

s = Sandbox(sessions=10)
s.age_lock(time.time() - 2 * DAY)
for i in range(5):
    f = s.proj / f"session-{i}.jsonl"
    os.utime(f, (LONG_AGO, LONG_AGO))
s.gate()
launched = s.dreamed()
check("the launch names a transcript new since the last dream",
      True, "session-9.jsonl" in launched)
check("the launch does not name a transcript older than the last dream",
      False, "session-0.jsonl" in launched)

s = Sandbox(sessions=30)
s.run("run")
launched = s.dreamed()
check("the transcript list is capped", 20, launched.count(".jsonl"))
check("the cap says how many were left out", True, "20 of 30" in launched)

s = Sandbox(sessions=0)
s.run("run")
launched = s.dreamed()
check("with no new transcripts the dream is launched without a list",
      False, "Transcripts new" in launched)


# --- The snapshot -----------------------------------------------------------
# A dream rewrites memory in place and that directory is under no version
# control, so a bad merge or an over-eager prune is unrecoverable without one.

s = Sandbox(sessions=10)
(s.proj / "memory" / "MEMORY.md").write_text("before")
s.gate()
s.dreamed()
check("the launch snapshots memory before dreaming",
      "before", (s.state / "memory-backup" / "MEMORY.md").read_text())

s = Sandbox(sessions=10)
(s.proj / "memory" / "MEMORY.md").write_text("before")
s.run("run")
(s.proj / "memory" / "MEMORY.md").write_text("after the dream")
(s.proj / "memory" / "invented.md").write_text("the dream added this")
r = s.run("restore")
check("restore puts the snapshot back",
      "before", (s.proj / "memory" / "MEMORY.md").read_text())
check("restore drops what the dream added",
      False, (s.proj / "memory" / "invented.md").exists())

s = Sandbox(sessions=10)
(s.proj / "memory" / "gone.md").write_text("dropped by the first dream")
s.run("run")
(s.proj / "memory" / "gone.md").unlink()
s.run("run")
check("a later snapshot replaces the earlier one, it does not merge with it",
      False, (s.state / "memory-backup" / "gone.md").exists())

s = Sandbox(sessions=10)
(s.proj / "memory" / "MEMORY.md").write_text("never dreamed")
r = s.run("restore")
check("restore without a snapshot leaves memory alone",
      "never dreamed", (s.proj / "memory" / "MEMORY.md").read_text())
check("restore without a snapshot says so", True, "no snapshot" in r.stdout.lower())


# --- run / reset / status ---------------------------------------------------

s = Sandbox(sessions=0)
s.age_lock(time.time())
s.run("run")
check("run launches a dream despite closed gates", False, s.quiet())

s = Sandbox(sessions=10)
s.age_lock(time.time())
s.run("reset")
check("reset clears the state directory", False, s.state.exists())
s.gate()
check("reset reopens the gates", False, s.quiet())

s = Sandbox(sessions=10)
check("status reports open gates on a cold project", True, "OPEN" in s.run("status").stdout)

s = Sandbox(sessions=10)
s.age_lock(time.time())
check("status reports a closed time gate", True, "CLOSED" in s.run("status").stdout)

s = Sandbox(sessions=10)
check("status reports no snapshot before the first dream",
      True, "snapshot      none" in s.run("status").stdout)
s.run("run")
s.dreamed()
check("status reports the snapshot once one exists",
      False, "snapshot      none" in s.run("status").stdout)

sys.exit(FAILED)
