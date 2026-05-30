# 2026-05-30 live TUI bidirectional sync

- fixed live Telegram-to-TUI injection by submitting pasted tmux turns with the Codex TUI composer keystroke instead of leaving the Telegram prompt stranded in the live pane
- serviced the shared TUI transcript before each `getUpdates` poll so TUI-originated mirroring keeps moving even when Telegram polling is idle or temporarily failing
