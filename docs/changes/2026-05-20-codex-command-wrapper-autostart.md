# Codex Command Wrapper Autostart

`telegram-codex` now installs a managed `codex` wrapper into the user PATH during normal skill installation.

The wrapper prefers:

- `~/.local/bin/codex`
- `~/bin/codex`

That path shadows the npm global Codex binary, starts one Telegram listener per Codex session when `TELEGRAM_BOT_TOKEN` is available, stores listener pid and log files under `~/.telegram-codex/<session-id>/`, and then execs the real Codex binary.

This fixes the earlier false assumption that `~/.developer-dashboard/cli/codex` was the active launcher for normal `codex` sessions.
