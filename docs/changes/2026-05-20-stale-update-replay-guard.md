# Stale Update Replay Guard

## Summary

`telegram-codex.listen` now guards against replaying stale Telegram updates across restarts.

## What Changed

- the listener now skips any returned Telegram update whose `update_id` is older than the next stored session offset
- if `listener.offset` is missing but `listener.inbox.jsonl` exists, the listener recovers the next offset from the latest inbox entry
- this blocks repeated append-and-reply churn for old Telegram messages when session state is imperfect

## Verification

- Docker functional gate passes for the full skill test suite
- Docker covered gate keeps `lib/Telegram/Codex/Manager.pm` at `100%` statement and `100%` subroutine coverage
