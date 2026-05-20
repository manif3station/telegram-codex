# 2026-05-20 DD Collector-Owned Telegram Polling

`telegram-codex` now uses a DD collector as the always-on Telegram polling runtime.

## What Changed

- `dashboard telegram-codex.start` now ensures exactly one `telegram-codex-<session-id>` collector exists in `~/.developer-dashboard/config/config.json`
- duplicate collector entries for the same session are removed automatically
- the collector shape is fixed to:
  - `interval: 5`
  - `rotation.lines: 100`
  - `cwd: <workspace where start ran>`
  - `command: dashboard telegram-codex.check-messages`
  - `mode: singleton`
- `dashboard telegram-codex.start` now persists the active Codex reply target in `~/.telegram-codex/<session-id>/codex.session`
- the collector-owned `dashboard telegram-codex.check-messages` loop replaces the old standalone listener as the primary always-on path

## Verification

- Docker functional gate passed at `Files=6, Tests=263`
- Docker covered gate passed with `lib/Telegram/Codex/Manager.pm` at `100.0%` statement and `100.0%` subroutine coverage
