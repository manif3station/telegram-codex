# Codex Session Telegram Replies

## Summary

Managed `telegram-codex.start` listener replies now come from the active Codex session instead of a static placeholder or acknowledgement string.

## What Changed

- inbound Telegram text messages in managed startup mode now resume the active Codex session
- the listener asks Codex to generate the exact Telegram reply text within that session context
- direct `telegram-codex.listen` stays passive by default unless explicit reply text is passed

## Verification

- Docker functional gate passes for the full skill test suite
- Docker covered gate keeps `lib/Telegram/Codex/Manager.pm` at `100%` statement and `100%` subroutine coverage
