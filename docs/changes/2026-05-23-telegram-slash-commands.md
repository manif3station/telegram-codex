# 2026-05-23 Telegram slash commands

- added Telegram-native slash command handling for paired managed sessions so `/status` and `/help` are answered directly by `telegram-codex`
- upgraded Telegram `/status` to capture the real live Codex TUI status panel from a tmux-backed shared session when available, and to return an explicit unavailable message instead of a synthetic local summary when no live pane exists
- accepted the normal Telegram `@botname` suffix form when parsing slash commands
- rejected unsupported Telegram slash commands explicitly instead of forwarding them into Codex as ordinary prompt text
