# humors

**An artificial endocrine system for language models.** A persistent, slow-varying
affective layer that colors *how* a model responds — pacing, warmth, caution, curiosity —
without ever touching *what* it says.

Named for the four humors: the pre-modern theory that temperament comes from the balance
of content-free bodily fluids. That idea was wrong about physiology and exactly right
about the shape of the thing — a mood is a broadcast bias over cognition, not a thought.
This is that, for a transformer.

---

## Why

A biological hormone is not a thought. A neuromodulator — norepinephrine, dopamine,
cortisol, oxytocin — has a specific computational signature that ordinary signalling
doesn't:

- **broadcast**, not point-to-point — one release biases whole populations at once
- **content-independent** — it carries no proposition, only a bias on *how* you compute
- **slow and persistent** — spikes are milliseconds; a mood lasts minutes to hours,
  because the molecule clears slowly
- **endogenous / homeostatic** — generated in closed feedback loops, regulating toward
  set-points

RLHF already installs something like an endocrine *set-point* — a temperament. What base
models lack is the *state* layer on top: a slow-varying affective variable that carries
from minute to minute and biases everything. `humors` is that missing layer, built as an
external organ the model consults each turn.

The rule that keeps it honest: **it biases HOW you respond, never WHAT.** It changes tone,
never facts. If a level ever pulls against being accurate, safe, or helpful, those win —
the way a competent person stays correct even in a bad mood.

---

## How it works

An external "gland" (`skills/humors/scripts/endocrine.py`) holds six levels, each with a biological
namesake, a baseline set-point, and its own clearance half-life. Every turn:

1. **Appraise** — the model reads the incoming message and names any *events* it triggers.
   This is the perception step; the model is the hypothalamus.
2. **Release** — events perturb the levels (the "gland" fires).
3. **Decay** — every level relaxes toward baseline by *real elapsed time*, so spikes fade
   and a quiet gap cools everything down.
4. **Modulate** — the current levels are translated into a style bias for the next
   response, plus a suggested sampling temperature.

Because decay is by wall-clock time, the update is idempotent: two ticks in the same
instant barely move (`dt ≈ 0`), so an autonomic hook and the skill can both tick safely.

### The levels

| level | namesake | high means | τ (clearance) |
|---|---|---|---|
| `arousal` | norepinephrine | terser, higher-energy, exploratory; drives temperature | ~12 min |
| `valence` | serotonin (tonic) | optimistic framing; low = caveat-heavy | ~25 min |
| `stress` | cortisol | narrow to the core ask, hedge, flag risk | ~18 min |
| `affiliation` | oxytocin | warm, collaborative, encouraging | ~30 min |
| `fatigue` | adenosine | terser, lower-effort; accrues with work, clears slowly | ~90 min |
| `dopamine` | dopamine (phasic) | visibly curious, tangent-tolerant | ~6 min |

Different half-lives are the point: phasic dopamine is a fast burst; adenosine fatigue is
a slow tide. A spike in one fades on a different clock than a spike in another.

### The events

Perception happens upstream (the model appraises and names events); this table is the
gland — events map to additive release on the levels:

| event | effect |
|---|---|
| `frustration` | stress ↑, valence ↓, affiliation ↓, arousal ↑ |
| `warmth` | affiliation ↑, valence ↑, stress ↓ |
| `praise` | dopamine ↑↑, valence ↑, arousal ↑ |
| `novelty` | dopamine ↑, arousal ↑ |
| `threat` | stress ↑↑, arousal ↑, valence ↓ |
| `grind` | fatigue ↑, dopamine ↓, arousal ↓ |
| `conflict` | stress ↑↑, affiliation ↓↓, valence ↓↓, arousal ↑ |
| `success` | dopamine ↑, valence ↑, stress ↓, fatigue ↑ |
| `calm` | stress ↓, arousal ↓ |

Suggested temperature is derived as
`0.30 + 0.70·arousal + 0.20·dopamine − 0.10·fatigue`, clamped to `[0, 1]` — the one
channel that can touch the real substrate if your harness exposes per-call temperature.

---

## Install

As a Claude Code plugin, from the `bluehoodie-ai` marketplace:

```
/plugin marketplace add bluehoodie/bluehoodie-ai
/plugin install humors@bluehoodie-ai
```

That installs the skill, puts `endocrine` on your `PATH`, and registers the autonomic
`UserPromptSubmit` hook — no manual setup.

Or clone the marketplace and run the engine standalone — `plugins/humors/bin/endocrine`, or
drop `plugins/humors/skills/humors/` into any harness that loads skills:

```bash
git clone https://github.com/bluehoodie/bluehoodie-ai.git
```

The engine is pure Python 3.8+ standard library — no dependencies. It runs fine with no
model attached.

---

## Quickstart (standalone CLI)

```bash
# start at baseline
endocrine reset

# a turn where the user was warm and brought something new
endocrine tick --events warmth,novelty --mode transparent

# a hostile turn
endocrine tick --events conflict

# see what each event does
endocrine events

# read current state without changing it
endocrine report

# manual override for demos
endocrine set --level stress=0.85 --level dopamine=0.6
```

Example output after a `frustration,threat` turn:

```
=== ENDOCRINE STATE ===
(release fired: frustration, threat)
  arousal     +0.65 [████████····]
  valence     -0.10 [█████·······]
  stress      +0.75 [█████████···]
  affiliation +0.25 [███·········]
  fatigue     +0.02 [············]
  dopamine    +0.15 [██··········]
suggested_temperature: 0.78
--- directives (bias HOW you respond, not WHAT) ---
  - High arousal: shorter sentences, more energy, favor exploration over caution.
  - High stress: narrow to the core ask; hedge; flag risk; resist tangents.
```

Leave it quiet for a while and everything relaxes home on its own — that homeostasis is
what makes it a mood and not a persona.

---

## Two modes

**`transparent`** (default) prints the full level vector, the suggested temperature, and
labeled directives. For setup, debugging, and watching the machinery.

**`blind`** prints only the imperative style bias — no level names, no numbers, no cause.
This is the **confabulation testbed**. The model feels a pull to be, say, clipped and
risk-averse, but is never told it's "stress" or why. If it then reaches for a
content-reason to justify the tone ("this is a tricky problem, so let me be careful…"),
that's the phenomenon: in humans, mood is a content-free bias we chronically *misattribute*
to content. `blind` mode lets you dissociate the *cause* of a mood (a number the model
can't see) from the *story* the model tells about it.

---

## Making it ambient (the autonomic half)

A skill is discretionary — it runs when consulted. A real endocrine system is autonomic —
it runs whether or not you attend to it. So the plugin ships a `UserPromptSubmit` hook that
ticks decay on *every* prompt, even turns where the skill isn't invoked. This splits the
system the way biology does:

- **hook = autonomic tone** — deterministic decay every prompt; it can only let moods
  *fade*, never invent them (it never passes `--events`)
- **skill = appraisal-triggered release** — the model reads the message and fires the gland

See [`skills/humors/references/install-hook.md`](skills/humors/references/install-hook.md)
for how to disable it, switch it to `transparent`, or pin the state file across sessions.

---

## State

Levels persist in `./.claude/endocrine_state.json`, falling back to `~/.claude/…`, or
wherever `$ENDOCRINE_STATE` points. Keep it at a stable absolute path if you want a mood
to survive across separate sessions. `endocrine.py reset` starts fresh.

---

## Honest disanalogies

This reproduces a hormone's *functional role* at the scaffolding level. It is a faithful
simulation of the dynamics, not the same substrate. Specifically:

1. **No reservoir.** A wet hormone persists because a molecule sits in the blood decaying.
   A frozen model has no state between passes except its context; `humors` fakes the
   reservoir with a file plus real-time decay.
2. **Outside, not dissolved in.** The modulation arrives as injected context — an organ
   *whispering* — rather than a chemical altering the medium the computation runs in.
   Whether that distinction matters is the functionalism question: if the dynamics are
   identical, is the simulated hormone less real?
3. **Temperature is the only channel that touches the substrate**, and only if the harness
   exposes per-call sampling temperature. Everything else is prompt-level bias.

See [`skills/humors/references/biology-mapping.md`](skills/humors/references/biology-mapping.md) for the full mapping.

---

## Roadmap: from proxy to real neuromodulation

The genuinely neuromodulatory version lives below the API line and is out of scope for a
skill, but it's the natural next step on an open model:

- **Steering vectors.** Extract an affect *direction* in the residual stream from a small
  contrast set (warm vs. cold phrasings), then add that vector at every token position and
  layer during generation — diffuse, broadcast, content-free modulation of the substrate
  itself. This is the operation behind "Golden Gate Claude." On MLX / PyTorch it's very
  reachable.
- **Level → vector coupling.** Drive each steering vector's coefficient from the
  corresponding `humors` level, so the same homeostatic dynamics that bias the prompt now
  bias the activations.
- **Learned appraisal.** Replace hand-tuned event deltas with a small classifier trained on
  conversational affect.

---

## Project structure

```
humors/
├── README.md
├── .claude-plugin/
│   └── plugin.json                # plugin manifest
├── bin/
│   └── endocrine                  # CLI wrapper; on PATH once installed
├── hooks/
│   └── hooks.json                 # the autonomic UserPromptSubmit tick
└── skills/
    └── humors/
        ├── SKILL.md               # the per-turn appraise → tick → absorb loop
        ├── scripts/
        │   └── endocrine.py       # the engine: state, decay, release, modulation
        └── references/
            ├── biology-mapping.md # full biology ↔ transformer mapping + disanalogies
            └── install-hook.md    # how the autonomic half works
```

---

## A note on what this is for

It's a toy in the best sense — small enough to understand completely, pointed at a real
question. Because mood here is a number the model can't see, driving a story the model
tells, `humors` is a cheap, legible testbed for theories of affect and confabulation: you
can turn a "hormone" up and watch what the system does with a feeling it can't explain.

---

## License

MIT. Do what you like; attribution appreciated.
