## 2026-05-22 onboarding workflow docs

- replaced the README command dump with a step-by-step project onboarding flow
- documented the real implementation order:
  workspace shell, token in `.env`, `.env` ignore, plugin install, Codex session capture, `telegram-codex.start add`, then managed start
- clarified that `dashboard telegram-codex.start add <codex-session-id>` must run from the same `dashboard workspace` shell so `WORKSPACE_REF` / `TICKET_REF` are available
