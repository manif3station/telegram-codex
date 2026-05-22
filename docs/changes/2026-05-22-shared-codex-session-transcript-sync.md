## 2026-05-22 shared Codex session transcript sync

- hydrated managed Telegram replies from recent persisted Codex session transcript rows for the saved session target
- normalized older raw Telegram bridge prompt rows into readable transcript lines before reuse as shared context
- journaled readable Telegram user and assistant turns back into the target Codex session transcript so later resumed TUI work and Telegram follow-up work share one persisted history
