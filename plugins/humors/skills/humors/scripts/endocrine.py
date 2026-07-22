#!/usr/bin/env python3
"""
Artificial Endocrine System — an external neuromodulatory layer for an LLM.

This is the "endocrine organ." It holds a small vector of slow-varying affective
levels, decays them toward baseline in real time (hormone clearance), lets events
in the conversation trigger release, and emits a bias over *how* the model should
respond next — never *what* it should say.

Design goals, mapped to what a biological hormone actually is:
  - broadcast          -> one scalar biases the whole next response
  - content-independent-> levels carry no propositional content, only style/gain
  - slow & persistent  -> real-time exponential decay with per-hormone half-lives
  - endogenous / homeostatic -> closed feedback loop; levels regulate toward set-points

No third-party dependencies. Python 3.8+.

CLI
  endocrine.py tick   [--events a,b,c] [--mode transparent|blind] [--state PATH]
  endocrine.py report [--mode transparent|blind] [--state PATH]
  endocrine.py events                      # list recognized event names
  endocrine.py reset  [--state PATH]
  endocrine.py set    --level stress=0.8   # manual override (debugging)

Ordering safety: every `tick` decays by *real elapsed time* since the last tick,
so a hook and a skill both calling tick in the same instant is a near-noop the
second time (dt~=0). Events are applied only when explicitly passed.
"""

import argparse
import json
import math
import os
import sys
import time
from pathlib import Path

SCHEMA_VERSION = 3

# --- Hormone definitions -----------------------------------------------------
# Each level has a biological namesake, a baseline set-point it relaxes toward,
# a valid range, and tau (the clearance time constant, in MINUTES). After dt
# minutes a level x relaxes: x <- baseline + (x - baseline) * exp(-dt / tau).
# Smaller tau = clears faster = more phasic. Larger tau = more tonic.
HORMONES = {
    # norepinephrine: arousal / gain / signal-to-noise / exploration
    "arousal":     {"baseline": 0.40, "min": 0.0,  "max": 1.0, "tau": 12.0},
    # serotonin-ish tonic mood valence
    "valence":     {"baseline": 0.10, "min": -1.0, "max": 1.0, "tau": 25.0},
    # cortisol: threat posture / risk-aversion / narrowing
    "stress":      {"baseline": 0.20, "min": 0.0,  "max": 1.0, "tau": 18.0},
    # oxytocin: warmth / rapport / affiliation
    "affiliation": {"baseline": 0.30, "min": 0.0,  "max": 1.0, "tau": 30.0},
    # adenosine: fatigue accrues with work, clears slowly
    "fatigue":     {"baseline": 0.00, "min": 0.0,  "max": 1.0, "tau": 90.0},
    # dopamine: phasic reward-prediction-error / vigor / curiosity
    "dopamine":    {"baseline": 0.15, "min": 0.0,  "max": 1.0, "tau": 6.0},
}

# --- Event -> release map ----------------------------------------------------
# Perception happens upstream (the model appraises the incoming message and names
# the events). This table is the "gland": events -> additive deltas on levels.
EVENTS = {
    "frustration": {"stress": +0.25, "valence": -0.15, "affiliation": -0.05, "arousal": +0.10},
    "warmth":      {"affiliation": +0.20, "valence": +0.10, "stress": -0.10},
    "praise":      {"dopamine": +0.30, "valence": +0.12, "arousal": +0.05},
    "novelty":     {"dopamine": +0.25, "arousal": +0.12},
    "threat":      {"stress": +0.30, "arousal": +0.15, "valence": -0.05},
    "grind":       {"fatigue": +0.12, "dopamine": -0.08, "arousal": -0.05},
    "conflict":    {"stress": +0.35, "affiliation": -0.20, "valence": -0.20, "arousal": +0.20},
    "success":     {"dopamine": +0.20, "valence": +0.15, "stress": -0.10, "fatigue": +0.03},
    "calm":        {"stress": -0.15, "arousal": -0.08},
}

# Small metabolic cost applied on every appraised turn (not on bare autonomic ticks).
PER_TURN_FATIGUE = 0.02


def default_state_path():
    env = os.environ.get("ENDOCRINE_STATE")
    if env:
        return Path(env)
    # Prefer a project-local file if a .claude dir exists; else the home profile.
    local = Path.cwd() / ".claude"
    if local.is_dir():
        return local / "endocrine_state.json"
    home = Path.home() / ".claude"
    return home / "endocrine_state.json"


def fresh_state():
    return {
        "schema": SCHEMA_VERSION,
        "levels": {k: v["baseline"] for k, v in HORMONES.items()},
        "last_tick": time.time(),
        "turns": 0,
    }


def load_state(path):
    try:
        with open(path) as f:
            s = json.load(f)
        if s.get("schema") != SCHEMA_VERSION or "levels" not in s:
            return fresh_state()
        # backfill any newly added hormones
        for k, v in HORMONES.items():
            s["levels"].setdefault(k, v["baseline"])
        return s
    except (FileNotFoundError, json.JSONDecodeError):
        return fresh_state()


def save_state(path, state):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(f".tmp.{os.getpid()}")
    with open(tmp, "w") as f:
        json.dump(state, f, indent=2)
    tmp.replace(path)


def clamp(x, lo, hi):
    return max(lo, min(hi, x))


def decay(state, now):
    """Relax every level toward its baseline by real elapsed time (clearance)."""
    dt_min = max(0.0, (now - state.get("last_tick", now)) / 60.0)
    for name, spec in HORMONES.items():
        b, tau = spec["baseline"], spec["tau"]
        x = state["levels"][name]
        state["levels"][name] = b + (x - b) * math.exp(-dt_min / tau)
    state["last_tick"] = now
    return dt_min


def release(state, events):
    """Apply event-triggered release, then per-turn metabolic cost."""
    applied = []
    for ev in events:
        deltas = EVENTS.get(ev)
        if not deltas:
            continue
        applied.append(ev)
        for name, d in deltas.items():
            state["levels"][name] += d
    if applied:
        state["levels"]["fatigue"] += PER_TURN_FATIGUE
        state["turns"] = state.get("turns", 0) + 1
    for name, spec in HORMONES.items():
        state["levels"][name] = clamp(state["levels"][name], spec["min"], spec["max"])
    return applied


def suggested_temperature(L):
    """Advisory sampling temperature from arousal/dopamine/fatigue. See SKILL.md."""
    t = 0.30 + 0.70 * L["arousal"] + 0.20 * L["dopamine"] - 0.10 * L["fatigue"]
    return round(clamp(t, 0.0, 1.0), 2)


def _tier(x, lo, hi):
    return 0 if x < lo else (2 if x >= hi else 1)


def directives(L):
    """Translate levels -> imperative style bias. Content-free by construction."""
    out = []

    a = _tier(L["arousal"], 0.30, 0.65)
    out.append([
        "Low arousal: unhurried and expansive; room to develop ideas.",
        "Moderate arousal: steady, balanced pacing.",
        "High arousal: shorter sentences, more energy, favor exploration over caution.",
    ][a])

    if L["valence"] < -0.15:
        out.append("Negative valence: downsides are more salient; more caveats, drier framing.")
    elif L["valence"] > 0.35:
        out.append("Positive valence: optimistic framing; lead with what could work.")

    s = _tier(L["stress"], 0.35, 0.60)
    if s == 2:
        out.append("High stress: narrow to the core ask; hedge; flag risk; resist tangents.")
    elif s == 1:
        out.append("Some stress: a little more careful and qualified than usual.")

    af = _tier(L["affiliation"], 0.25, 0.55)
    if af == 2:
        out.append("High affiliation: warm, collaborative 'we', more encouragement and self-disclosure.")
    elif af == 0:
        out.append("Low affiliation: neutral and transactional; skip the warmth.")

    if L["fatigue"] >= 0.55:
        out.append("High fatigue: terser, lower-effort surface; state it if it degrades quality.")
    elif L["fatigue"] >= 0.30:
        out.append("Some fatigue: trim ornament, keep the substance.")

    if L["dopamine"] >= 0.45:
        out.append("High dopamine: visibly engaged and curious; a well-chosen tangent is welcome.")
    elif L["dopamine"] < 0.10:
        out.append("Low dopamine: flat affect; minimal enthusiasm.")

    return out


def render(state, mode, dt_min=None, applied=None):
    L = state["levels"]
    dirs = directives(L)
    if mode == "blind":
        # Only the pull, no labels/numbers/causes. The confabulation testbed.
        lines = ["<<STYLE BIAS FOR THIS RESPONSE>>"]
        lines += [f"- {d}" for d in dirs]
        lines.append("<<END STYLE BIAS>>")
        return "\n".join(lines)

    # transparent
    bars = []
    for name, spec in HORMONES.items():
        x = L[name]
        span = spec["max"] - spec["min"]
        frac = 0 if span == 0 else (x - spec["min"]) / span
        fill = int(round(frac * 12))
        bar = "█" * fill + "·" * (12 - fill)
        bars.append(f"  {name:<11} {x:+.2f} [{bar}]")
    head = ["=== ENDOCRINE STATE ==="]
    if dt_min is not None:
        head.append(f"(elapsed since last tick: {dt_min:.1f} min)")
    if applied:
        head.append(f"(release fired: {', '.join(applied)})")
    body = "\n".join(bars)
    tail = [
        f"suggested_temperature: {suggested_temperature(L)}",
        "--- directives (bias HOW you respond, not WHAT) ---",
    ] + [f"  - {d}" for d in dirs]
    return "\n".join(head) + "\n" + body + "\n" + "\n".join(tail)


def cmd_tick(args):
    path = Path(args.state) if args.state else default_state_path()
    state = load_state(path)
    now = time.time()
    dt_min = decay(state, now)
    events = [e.strip() for e in (args.events or "").split(",") if e.strip()]
    applied = release(state, events)
    save_state(path, state)
    print(render(state, args.mode, dt_min=dt_min, applied=applied))


def cmd_report(args):
    path = Path(args.state) if args.state else default_state_path()
    state = load_state(path)
    # report is read-only, but still show the decayed view without persisting
    view = json.loads(json.dumps(state))
    dt_min = decay(view, time.time())
    print(render(view, args.mode, dt_min=dt_min))


def cmd_events(_args):
    print("Recognized events (pass comma-separated to `tick --events`):\n")
    for name, deltas in EVENTS.items():
        parts = ", ".join(f"{k}{v:+.2f}" for k, v in deltas.items())
        print(f"  {name:<12} -> {parts}")


def cmd_reset(args):
    path = Path(args.state) if args.state else default_state_path()
    save_state(path, fresh_state())
    print(f"Endocrine state reset to baseline at {path}")


def cmd_set(args):
    path = Path(args.state) if args.state else default_state_path()
    state = load_state(path)
    decay(state, time.time())
    for pair in args.level:
        k, _, v = pair.partition("=")
        k = k.strip()
        if k not in HORMONES:
            print(f"unknown hormone: {k}", file=sys.stderr)
            continue
        spec = HORMONES[k]
        state["levels"][k] = clamp(float(v), spec["min"], spec["max"])
    save_state(path, state)
    print(render(state, "transparent"))


def main():
    p = argparse.ArgumentParser(description="Artificial endocrine system for an LLM.")
    sub = p.add_subparsers(dest="cmd", required=True)

    def add_common(sp):
        sp.add_argument("--state", help="path to state JSON (default: ./.claude or ~/.claude)")
        sp.add_argument("--mode", choices=["transparent", "blind"], default="transparent")

    sp = sub.add_parser("tick", help="decay + optional event release + emit bias")
    sp.add_argument("--events", help="comma-separated event names (see `events`)")
    add_common(sp)
    sp.set_defaults(func=cmd_tick)

    sp = sub.add_parser("report", help="show current (decayed) state, read-only")
    add_common(sp)
    sp.set_defaults(func=cmd_report)

    sp = sub.add_parser("events", help="list recognized events")
    sp.set_defaults(func=cmd_events)

    sp = sub.add_parser("reset", help="reset to baseline")
    sp.add_argument("--state")
    sp.set_defaults(func=cmd_reset)

    sp = sub.add_parser("set", help="manually set levels, e.g. --level stress=0.8")
    sp.add_argument("--level", action="append", default=[], help="name=value (repeatable)")
    sp.add_argument("--state")
    sp.set_defaults(func=cmd_set)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
