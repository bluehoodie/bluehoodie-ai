# The autonomic half (the `UserPromptSubmit` hook)

A skill is *discretionary* — it runs when consulted. A real endocrine system is
*autonomic* — it runs whether or not you attend to it. So the plugin ships a
`UserPromptSubmit` hook (`hooks/hooks.json`) that ticks decay on every prompt, keeping the
state drifting home even on turns where the skill is never invoked. Installing the plugin
installs the hook; there is no manual setup step.

Division of labor (this mirrors the biology):
- **Hook = autonomic tone.** Deterministic decay toward baseline, every prompt, no
  appraisal. Cheap, involuntary.
- **Skill = appraisal-triggered release.** The model reads the message, names events,
  applies release. Deliberate, perception-driven.

Because `tick` decays by *real elapsed time* since the last tick, the hook and the skill
can both tick in the same turn safely — the second tick sees `dt ≈ 0` and barely moves.

The hook only ever **decays** (it never passes `--events`), so it cannot invent a mood — it
can only let an existing one fade. All *release* stays in the skill, gated by the model's
appraisal. That keeps the autonomic half incapable of fabricating affect.

## What it runs

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ {
        "type": "command",
        "command": "\"${CLAUDE_PLUGIN_ROOT}/bin/endocrine\" tick --mode blind",
        "timeout": 5
      } ] }
    ]
  }
}
```

A `UserPromptSubmit` hook's stdout is injected into the model's context, so the ambient
bias rides in on every prompt automatically. `--mode blind` means it arrives without labels
or numbers (the confabulation setup); switch to `--mode transparent` in `hooks/hooks.json`
if you'd rather watch the state every turn.

## Pinning state across projects

By default the state file is per-project (`./.claude/endocrine_state.json`, falling back to
`~/.claude/`), so each repo carries its own mood. To make one mood follow you everywhere:

```bash
export ENDOCRINE_STATE="$HOME/.claude/endocrine_state.json"
```

Put that in your shell profile, or in `"env"` in `settings.json`.

## Turning it off

Disable the plugin with `/plugin`, or delete the `UserPromptSubmit` block from
`hooks/hooks.json`. The skill still works on its own — you just lose the involuntary decay
between invocations.

## Verifying

Run any prompt, then `endocrine report`. `turns` won't change (the hook doesn't count
turns) but `last_tick` should be recent.
