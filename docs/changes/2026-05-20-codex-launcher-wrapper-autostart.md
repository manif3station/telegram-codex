# Codex Launcher Wrapper Autostart

`dashboard telegram-codex.install` now writes a Codex launcher wrapper to:

- `~/.developer-dashboard/cli/codex`

That wrapper starts one `telegram-codex` listener for the active Codex session
before it execs the real Codex binary.

Wrapper-managed runtime files live under:

- `~/.telegram-codex/<session-id>/listener.pid`
- `~/.telegram-codex/<session-id>/listener.log`
- `~/.telegram-codex/<session-id>/listener.offset`
- `~/.telegram-codex/<session-id>/listener.inbox.jsonl`

The wrapper uses this session id precedence:

1. `TELEGRAM_CODEX_SESSION_ID`
2. `CODEX_SESSION_ID`
3. `default`
