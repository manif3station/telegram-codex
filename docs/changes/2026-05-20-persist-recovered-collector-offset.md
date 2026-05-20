# Persist Recovered Collector Offset

## Summary

The collector-owned `dashboard telegram-codex.check-message <session-id>` worker now writes any recovered inbox-ledger next offset back to `~/.telegram-codex/<session-id>/listener.offset` before polling.

## Why

The earlier collector fix already recovered the correct next offset in memory from `listener.inbox.jsonl`, but the older on-disk `listener.offset` file could remain stale until a later new message arrived. That made restart diagnostics look wrong and confused replay investigation even though the worker had already recovered the correct offset internally.

## Result

- missing `listener.offset` files are recreated immediately from the inbox ledger when recovery succeeds
- stale `listener.offset` files are rewritten to the newer recovered offset before the next Telegram poll
- collector restart state, inbox-ledger truth, and replay diagnostics now stay aligned on disk

## Verification

- Docker functional gate passed at `Files=6, Tests=282`
- Docker covered gate passed at `Files=6, Tests=282`
- `lib/Telegram/Codex/Manager.pm` statement coverage `100.0`
- `lib/Telegram/Codex/Manager.pm` subroutine coverage `100.0`
