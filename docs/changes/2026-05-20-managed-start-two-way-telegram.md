# Managed Start Two-Way Telegram

## Summary

`dashboard telegram-codex.start` now launches the Telegram listener in stable two-way mode instead of passive capture mode.

## What Changed

- managed startup now passes the concise acknowledgement reply `Message received. Codex is active here.` into the listener
- direct `telegram-codex.listen` remains passive by default unless explicit reply text is passed
- the listener now survives transient `getUpdates` transport failures by recording the error, pausing briefly, and continuing
- stale stored offsets are now clamped up to the newer inbox-ledger offset so duplicated older Telegram updates are not replayed

## Verification

- Docker functional gate passes for the full skill test suite
- Docker covered gate keeps `lib/Telegram/Codex/Manager.pm` at `100%` statement and `100%` subroutine coverage
