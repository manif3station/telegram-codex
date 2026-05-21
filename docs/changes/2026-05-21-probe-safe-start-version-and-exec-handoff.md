# 2026-05-21 Probe-Safe Start Version And `exec` Handoff

- made `dashboard telegram-codex.start --version` return version metadata without creating or restarting the managed Telegram collector
- aligned the start command with DD probe/discovery behavior so repeated `cli/start --version` checks are harmless metadata reads instead of startup side effects
- changed successful Codex and Ollama launch handoff from `system(...)` to `exec` so the wrapper does not stay resident as an extra long-lived `cli/start` parent process
