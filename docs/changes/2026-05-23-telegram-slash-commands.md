# 2026-05-23 Telegram slash commands

- added Telegram-native slash command handling for paired managed sessions so `/status` and `/help` are answered directly by `telegram-codex`
- upgraded Telegram `/status` to capture the real live Codex TUI status panel from a tmux-backed shared session when available, and to return an explicit unavailable message instead of a synthetic local summary when no live pane exists
- fixed the live `/status` path so a pane that is already showing the real Codex status panel is returned immediately instead of timing out on an unchanged visible block
- added Docker-safe regression coverage for the real `tmux capture-pane` shell-out branch with a fake `tmux` binary on `PATH`
- accepted the normal Telegram `@botname` suffix form when parsing slash commands
- rejected unsupported Telegram slash commands explicitly instead of forwarding them into Codex as ordinary prompt text
