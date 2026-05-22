# 2026-05-22 unpaired trigger messages stop at pairing boundary

- the first unpaired Telegram trigger message still returns the local `d2 telegram-codex.pair <hexcode>` reply
- unpaired trigger messages now stop before any Codex-session preparation path
- that means no Codex resume, no live tmux-backed TUI injection, and no shared-transcript append until the chat is paired
