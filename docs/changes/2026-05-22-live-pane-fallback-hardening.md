# 2026-05-22 live-pane fallback hardening

- live Telegram/TUI sync now prefers the freshest tmux-backed `codex resume <session-id>` process instead of the first stale match for the same session
- if the injected Telegram turn never appears in the live transcript, the worker fails fast, records `codex.live_pane.fallback`, and retries through detached `codex exec resume`
- if the live transcript records the Telegram user turn but never reaches a final assistant answer, that timeout path is covered directly so Telegram does not silently stall behind the kickoff line without diagnostic coverage
