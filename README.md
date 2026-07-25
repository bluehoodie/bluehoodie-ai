# bluehoodie-ai

A Claude Code plugin marketplace for toy AI research — small, legible experiments in how
language models behave.  All plugins are experimental and for research purposes only.  

Not intended for production use.

## Use it

```
/plugin marketplace add bluehoodie/bluehoodie-ai
/plugin install <name>@bluehoodie-ai
```

## Plugins

| plugin | what it does |
|---|---|
| [`humors`](plugins/humors) | An artificial endocrine system. A persistent, slow-varying affective state — arousal, valence, stress, affiliation, fatigue, dopamine — that decays in real time and biases *how* Claude responds, never *what*. Doubles as a confabulation testbed. |

## Adding a plugin

Plugins live in `plugins/<name>/` in this repo. Add an entry to
[`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json):

```json
{
  "name": "thing",
  "description": "…",
  "source": "./plugins/thing",
  "category": "research"
}
```

Each plugin directory needs a `.claude-plugin/plugin.json`, plus whatever it ships —
`skills/`, `commands/`, `agents/`, `hooks/hooks.json`, `bin/` (auto-added to `PATH`).

Validate before pushing:

```bash
claude plugin validate . --strict
claude plugin validate plugins/thing --strict
```

## License

MIT.
