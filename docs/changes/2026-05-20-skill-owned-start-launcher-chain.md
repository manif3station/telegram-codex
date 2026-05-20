# Skill-Owned Start Launcher Chain

## Summary

`telegram-codex` now owns the real Codex startup logic through `dashboard telegram-codex.start` and `./cli/start`.

## What Changed

- `~/.developer-dashboard/cli/codex` is now a thin handoff launcher into `dashboard telegram-codex.start`
- the managed user-PATH `codex` helper is now also a thin handoff into `~/.developer-dashboard/cli/codex`
- the skill-owned `start` logic preserves the original saved-session resume mapping from `TICKET_REF` and `~/.developer-dashboard/config/codex.json`
- the per-session listener runtime now includes `listener.pid` and `listener.log` paths alongside `listener.offset` and `listener.inbox.jsonl`
- listener reply-send failures now still persist the next offset so one Telegram `429` or similar reply error cannot cause restart-time message replay spam

## Verification

- Docker functional gate passes for the full skill test suite
- Docker covered gate keeps `lib/Telegram/Codex/Manager.pm` at `100%` statement and `100%` subroutine coverage, using `cover -ignore_covered_err` only for the intentional child-process stdio redirection statements marked `# uncoverable statement`
