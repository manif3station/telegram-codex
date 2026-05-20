# Passive Listener Default

## Summary

`telegram-codex.listen` now captures inbound Telegram updates by default without sending a placeholder bot acknowledgement.

## What Changed

- the listener no longer uses the built-in `queued for Codex` reply text when no explicit reply text is provided
- explicit acknowledgement replies still work when a reply text is passed on the command line
- `/start` readiness replies remain available through `dashboard telegram-codex.auto-reply-start`

## Verification

- Docker functional gate passes for the full skill test suite
- Docker covered gate keeps `lib/Telegram/Codex/Manager.pm` at `100%` statement and `100%` subroutine coverage
