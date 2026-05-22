# Telegram Session Pairing Security

## Summary

Managed `telegram-codex` sessions now require a local pairing step before any Telegram chat can drive the active Codex session.

## Details

- the first unpaired Telegram message receives one local pairing command reply in the form `d2 telegram-codex.pair <hexcode>`
- later unpaired messages are ignored until the local pair command is run
- `dashboard telegram-codex.pair <hexcode>` binds the pending Telegram chat to the current workspace session
- after pairing, only that paired Telegram chat can drive the session and outsider chats are ignored

## Verification

- Docker functional gate passed at `Files=6, Tests=515`
- Docker covered gate passed at `Files=6, Tests=515`
- `lib/Telegram/Codex/Manager.pm` statement coverage `100.0`
- `lib/Telegram/Codex/Manager.pm` subroutine coverage `100.0`
