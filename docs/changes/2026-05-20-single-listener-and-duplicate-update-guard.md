# Single Listener And Duplicate Update Guard

## Summary

Managed startup now reuses the existing listener for a session, and the listener skips any Telegram update already recorded in that session inbox ledger.

## What Changed

- managed startup verifies and reuses the resident listener for the same session instead of spawning a duplicate
- the listener pid file is refreshed to the real session listener pid
- the listener skips any `update_id` already present in `listener.inbox.jsonl`

## Verification

- Docker functional gate passes for the full skill test suite
- Docker covered gate keeps `lib/Telegram/Codex/Manager.pm` at `100%` statement and `100%` subroutine coverage
