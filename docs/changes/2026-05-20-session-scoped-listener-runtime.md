# Session-Scoped Listener Runtime

`telegram-codex` listener state is now partitioned by Codex session id under `~/.telegram-codex/`.

The listener now keeps:

- `~/.telegram-codex/<session-id>/listener.offset`
- `~/.telegram-codex/<session-id>/listener.inbox.jsonl`

Session id resolution order is:

1. `TELEGRAM_CODEX_SESSION_ID`
2. `CODEX_SESSION_ID`
3. `default`

This prevents separate Codex sessions from sharing one Telegram offset or one mixed inbox ledger by accident.
