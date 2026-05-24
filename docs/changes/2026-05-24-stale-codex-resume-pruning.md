# 2026-05-24 stale codex resume pruning

- added stale duplicate `codex resume <session-id>` pruning at `check-message` startup so collector-owned Telegram sessions stop accumulating older orphan live-session processes on the same tty
- Codex process discovery now captures parent pid data so the worker only prunes clearly stale orphan duplicates and keeps the freshest tmux-backed session owner intact
- added Docker-verified regressions for stale-process selection, TERM success, and TERM-then-KILL escalation, with audit rows recorded for each pruned pid
