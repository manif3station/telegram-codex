# Direct Managed Listener Launch

## Summary

Managed `telegram-codex.start` now launches the skill-owned `cli/listen` command directly so the listener pid file tracks the real resident listener.

## What Changed

- removed the nested `dashboard telegram-codex.listen` process hop from managed startup
- launch now goes straight to the skill-owned `cli/listen` entrypoint
- listener pid tracking is aligned to the actual resident listener process

## Verification

- Docker functional gate passes for the full skill test suite
- Docker covered gate keeps `lib/Telegram/Codex/Manager.pm` at `100%` statement and `100%` subroutine coverage
