# Changelog

## 2.1.0

- Snapshot `memory/` into the state directory before every dream, and add a
  `restore` verb plus `/dream:dream-restore` to put it back. A dream rewrites
  memory in place and that directory is under no version control, so a bad merge
  or an over-eager prune had nothing to fall back on. One snapshot per project,
  replaced on each launch — merging would resurrect files an earlier dream
  deleted on purpose.
- Name the transcripts written since the last dream in the launch prompt, newest
  first, capped at 20. The gate already computed that set for the session gate;
  handing it over bounds "grep recent sessions", which otherwise pointed at a
  directory that also holds sessions an earlier dream already mined.
- `status` reports whether a snapshot exists and when it was taken.

## 2.0.0

- Collapse the plugin onto a single gate script and one prompt: the hook,
  `/dream:dream`, and the launched session all run the same skill, so the
  automatic and manual paths cannot drift apart.

## 1.2.0

- Launch the dream from the gate hook instead of suggesting one. Injected
  context is advisory, and across 25 sessions where the "consolidation is due"
  notice fired it was acted on zero times.

## 1.1.2

- Count the session being started in the session gate. `SessionStart` fires
  before its transcript is written, so counting only what was on disk opened the
  gate a session late.

## 1.1.1

- Treat a missing or empty memory directory as dreamable rather than a gate —
  that is the state of a project whose first consolidation has the most to do.

## 1.1.0

- Run the consolidation in a model-pinned background session, keeping it off an
  expensive session model and out of the session's context window.

## 1.0.1

- Fix the duplicate hooks load caused by the `hooks` key in `plugin.json`.

## 1.0.0

- Initial release.
