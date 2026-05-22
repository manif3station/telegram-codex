# 2026-05-22 live tmux session sync

## Summary

`telegram-codex` now supports true live Telegram and Codex TUI turn sharing when the mapped Codex session is already open in a tmux-backed TUI.

## What Changed

- Telegram-managed inbound messages now try to locate the live `codex resume <session-id>` process and match its tty back to a tmux pane.
- When that pane is found, the worker injects the Telegram prompt into the already-open TUI instead of falling back immediately to detached `codex exec resume`.
- The worker tails the shared Codex transcript for commentary and final-answer rows so the paired Telegram chat receives progress and final delivery from the same live turn.
- TUI-originated turns are mirrored back to the paired Telegram chat by tailing the same transcript and tracking `~/.telegram-codex/<session-id>/transcript.cursor`.
- If no live tmux-backed pane can be found for the mapped session, the runtime falls back cleanly to the existing detached `codex exec resume` path.

## Verification

- Docker functional gate: `Files=6, Tests=585`, `PASS`
- Docker covered gate: `Files=6, Tests=585`, `PASS`
- `lib/Telegram/Codex/Manager.pm` statement `100.0`
- `lib/Telegram/Codex/Manager.pm` subroutine `100.0`
