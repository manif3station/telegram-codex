# Managed Typing Until Final Delivery

## Summary

The managed collector-owned Telegram reply path now keeps Telegram `typing...` status active until the final outbound reply send attempt completes, instead of stopping as soon as Codex finishes generating reply text.

## What Changed

- moved the managed typing guard to cover both Codex reply generation and the final Telegram delivery step
- kept typing guard cleanup correct when Codex reply generation fails
- kept typing guard cleanup correct when the final Telegram send fails

## Verification

- Docker functional gate passes for the `telegram-codex` skill
- Docker covered gate proves `lib/Telegram/Codex/Manager.pm` stays at `100.0%` statement and `100.0%` subroutine coverage
