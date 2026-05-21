# Verbose Codex Step Streaming In Telegram

## Summary

Managed `telegram-codex` replies now stream real step-by-step Codex events from `codex exec resume --json` into Telegram instead of showing the placeholder `Codex is still working on your request...` heartbeat.

## What Changed

- the managed reply subprocess now runs with `--json` and parses Codex event lines as they happen
- agent messages and command execution events are reformatted into a readable Telegram verbose trace
- the trace message is updated in place and preserved in chat instead of being deleted as a generic progress heartbeat
- Telegram `typing...` stays active until the final outbound reply send attempt completes

## Verification

- Docker functional gate passed with `Files=6, Tests=429`
- Docker covered gate passed with `Files=6, Tests=429`
- `lib/Telegram/Codex/Manager.pm` stayed at `100.0%` statement and `100.0%` subroutine coverage
