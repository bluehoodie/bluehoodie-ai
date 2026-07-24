#!/usr/bin/env bash
# Dream status line segment — prints one line when consolidation is due, nothing
# otherwise. Add it to your own status line script (see README, "Status line"):
#
#   bash /path/to/plugins/dream/scripts/dream-segment.sh
#
# Deliberately does no work: status lines re-run on a 300ms debounce, so the
# gate verdict is precomputed by gate-check.sh at SessionStart and read here as
# a single file test. Reads nothing from stdin, so it is safe to call after your
# script has already consumed the status line JSON payload.

[ -f "$HOME/.claude/dream-plugin-state/.due" ] &&
  printf '\033[2m💤 dream due — run /dream:dream\033[0m\n'

exit 0
