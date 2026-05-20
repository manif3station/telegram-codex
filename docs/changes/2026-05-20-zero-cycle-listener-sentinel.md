# Zero-Cycle Listener Sentinel

## Summary

`telegram-codex.listen 0 ...` now uses `0` as the run-forever sentinel instead of stopping after the first poll cycle.

## What Changed

- the listener argument parser now treats `MAX_CYCLES=0` as an unlimited run
- managed `telegram-codex.start` keeps its resident listener because it launches `telegram-codex.listen 0 30`
- direct listener usage docs now explain the zero-cycle sentinel clearly

## Verification

- Docker functional gate passes for the full skill test suite
- Docker covered gate keeps `lib/Telegram/Codex/Manager.pm` at `100%` statement and `100%` subroutine coverage
