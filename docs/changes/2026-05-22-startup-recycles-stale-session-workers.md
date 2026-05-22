# 2026-05-22 startup recycles stale session workers

- made `dashboard telegram-codex.start` recycle any already-running
  per-session `dashboard telegram-codex.check-message <session-id>` worker
  before restarting the DD collector
- fixed the case where `--audit` or newer progress-stream logic looked
  broken only because an older long-lived worker from a previous release was
  still running for that session
