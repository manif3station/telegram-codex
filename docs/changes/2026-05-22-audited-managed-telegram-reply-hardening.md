# 2026-05-22 audited managed Telegram reply hardening

- added `dashboard telegram-codex.start --audit`, which enables per-session
  runtime audit capture under `~/.telegram-codex/<session-id>/audit.jsonl`
- hardened the managed Telegram verbose-progress reporter so failed
  `sendMessage` or `editMessageText` calls do not abort the active reply
  mid-operation
- upgraded the real `codex exec resume` path to capture streamed progress
  events, progress callback failures, exit code, signal, and stderr tail so
  cut-off Telegram tasks can be diagnosed instead of collapsing into a
  generic reply failure
