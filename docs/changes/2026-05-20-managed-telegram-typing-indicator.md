# Managed Telegram Typing Indicator

## Summary

The managed collector-owned Telegram reply path now sends Telegram `typing...` status before Codex generates the final reply text.

## Why

Without a chat action, Telegram users could not tell whether Codex had seen the message and was still working. The message would appear idle until the final reply arrived.

## Result

- managed collector-owned replies now send `sendChatAction` with `typing`
- the typing indicator is shown before the Codex-generated `sendMessage`
- typing-action failures are non-fatal and do not block the final reply

## Verification

- Docker functional gate passed at `Files=6, Tests=292`
- Docker covered gate passed with `lib/Telegram/Codex/Manager.pm` statement `100.0`
- Docker covered gate passed with `lib/Telegram/Codex/Manager.pm` subroutine `100.0`
