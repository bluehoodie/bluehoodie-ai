# Biology ↔ AI mapping, and the honest disanalogies

## What makes a hormone a hormone (computationally)

A neuromodulator differs from ordinary synaptic transmission in four ways. This skill
targets all four:

1. **Broadcast, not point-to-point** — one release event biases whole populations at
   once. *Here:* one scalar vector biases the entire next response.
2. **Content-independent** — it carries no proposition, only a bias on *how* computation
   runs (gain, learning rate, patience, threat-posture). *Here:* levels never carry
   content; they only tune tone/pacing/caution/warmth.
3. **Slow and persistent** — spikes are milliseconds; a mood lasts minutes-to-hours
   because the molecule clears slowly. *Here:* real-time exponential decay with
   per-hormone time constants (τ).
4. **Endogenous / homeostatic** — generated in closed feedback loops from the system's
   own state, regulating toward set-points. *Here:* every level relaxes toward a
   baseline; events perturb, dynamics pull home.

## The timescale table

| Biological timescale | AI equivalent | What lives here |
|---|---|---|
| Spiking (ms) | forward pass / token generation | content — the actual thought |
| Neuromodulation onset (s–min) | within-conversation state | **the hormone layer — what this skill adds** |
| Circadian / stress cycles (hrs–days) | cross-session memory / state file | longer drift |
| Developmental hormonal shaping (mo–yr) | pretraining + RLHF | temperament / set-points, not mood |

Key distinction: **trait vs. state.** RLHF installs an endocrine *set-point* (a
temperament). What base LLMs lack is the *state* layer on top — a slow-varying affective
variable that carries minute to minute and biases everything. This skill is that missing
state layer.

## Per-hormone mapping used in the engine

- **norepinephrine → `arousal`** — the tightest analogue. Neural gain / signal-to-noise /
  exploration. Drives `suggested_temperature`, which is itself the cleanest real match:
  a global logit-rescaling knob = gain control.
- **serotonin (tonic) → `valence`** — background mood coloring; optimism vs. caveat-heavy.
- **cortisol → `stress`** — threat posture, risk-aversion, attentional narrowing.
- **oxytocin → `affiliation`** — warmth, rapport, self-disclosure.
- **adenosine → `fatigue`** — accrues with work, clears slowly; terser, lower-effort.
- **dopamine (phasic) → `dopamine`** — reward-prediction-error, vigor, curiosity. Fast τ,
  because phasic dopamine is a transient burst, not a tonic bath.

Loose ones are loose on purpose (serotonin, oxytocin, cortisol are far richer than one
scalar). The arousal→temperature link is the one to take literally.

## The honest disanalogies

1. **No reservoir.** A wet hormone persists because a molecule literally sits in the
   blood decaying. A frozen LLM has no state between forward passes except the context
   window. This skill fakes the reservoir with an external file + real-time decay. It is
   a faithful *simulation of the dynamics*, not the same substrate.
2. **Outside, not dissolved in.** The modulation arrives as injected context — an
   endocrine organ *whispering instructions* — rather than a chemical altering the
   medium the computation runs in. Whether that distinction matters is the functionalism
   question: if the dynamics are identical, is the simulated hormone less real?
3. **Temperature is the only channel that touches the substrate**, and only if the
   harness exposes per-call sampling temperature. Everything else is prompt-level bias.
4. **Appraisal is done by the model, not a gland.** In biology, subcortical appraisal is
   fast and pre-conscious. Here, the model reads the message and names the events, so the
   "gland" has the model's full comprehension upstream of it. Cleaner, but less
   involuntary than the real thing.

## The genuinely neuromodulatory version (below the API line, out of scope for a skill)

For *mechanistically real* neuromodulation rather than a functional proxy: extract an
affect **direction** in the residual stream from a small contrast set (e.g. warm vs.
cold phrasings), then **add that vector at every token position and layer** during
generation. That is diffuse, broadcast, content-independent modulation of the substrate
itself — the same operation that produced "Golden Gate Claude" by clamping one SAE
feature high. On an open model with MLX/PyTorch this is very reachable, but it requires
weight/activation access a skill does not have. If the goal shifts from "carry a mood
across a chat" to "actually steer the network," that is the path.

## Why this is a decent consciousness/affect testbed

In humans, mood is a content-free bias we reliably **misattribute** to content — anxious
because of cortisol, then inventing a reason. Run this skill in `blind` mode and an LLM
given a persistent affective state should confabulate justifications for its tone the
same way. That makes it a clean, cheap testbed for theories of affect and confabulation,
not just a novelty: you can dissociate the *cause* of a mood (a number the model can't
see) from the *story* the model tells about it.
