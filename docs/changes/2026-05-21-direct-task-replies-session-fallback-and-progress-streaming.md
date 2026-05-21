# 2026-05-21 Direct Task Replies, Session Fallback, And Progress Streaming

- managed Telegram prompts now tell resumed Codex sessions to answer directly without boilerplate prefaces unless the user explicitly asked for them
- task-style Telegram requests now require real in-session work before reply, and promise-only placeholders such as `will be done` trigger one stricter retry instead of being sent to Telegram
- when `codex.session` is missing, the managed reply path now falls back to the saved-session mapping in `~/.developer-dashboard/config/codex.json`
- managed Telegram task replies now keep a separate in-progress status message alive while the resumed Codex session is still working, alongside the existing `typing...` indicator
