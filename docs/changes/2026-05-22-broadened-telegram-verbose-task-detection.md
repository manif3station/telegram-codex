# Broadened Telegram Verbose Task Detection

## Summary

Managed Telegram verbose progress now starts for broader task-style requests and emits an immediate kickoff line before delayed Codex JSON events arrive.

## Details

- widened task detection so requests like `Run all the tests and check if any test not good enough` are treated as completion-style work
- emits `Resuming active Codex session` before richer `codex exec resume --json` events arrive
- formats `thread.started` as `Session resumed` so minimal event streams still produce visible progress

## Verification

- Docker functional gate passed at `Files=6, Tests=484`
- Docker covered gate passed at `Files=6, Tests=484`
- `lib/Telegram/Codex/Manager.pm` statement coverage `100.0`
- `lib/Telegram/Codex/Manager.pm` subroutine coverage `100.0`
