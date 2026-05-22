# 2026-05-22 managed start bypass flag

- made `dashboard telegram-codex.start` prepend `--dangerously-bypass-approvals-and-sandbox` before it hands off to the real Codex process
- kept the managed start argv idempotent so an already-present bypass flag is not duplicated
- preserved the same no-approval launch contract on the explicit Telegram-owned Ollama launch profile path
