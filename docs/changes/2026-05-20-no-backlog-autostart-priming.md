# No Backlog Autostart Priming

Managed `codex` auto-start for `telegram-codex` now primes the listener offset to the latest Telegram update on first start when no stored offset exists.

That means:

- old pending Telegram backlog messages are not auto-replied
- the listener begins replying only to new inbound messages that arrive after startup
- later runs still resume from the stored `~/.telegram-codex/<session-id>/listener.offset`
