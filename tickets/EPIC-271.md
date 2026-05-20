# EPIC-271

## Summary

Add a governed `telegram-codex` skill that bridges Telegram Bot API into a local Codex plugin and stdio MCP server, then extend it with DD-collector-owned always-on polling, per-session runtime state, a managed `codex` launcher path that starts the Telegram collector automatically while preserving the original saved-session resume flow, and replay guards that stop stale Telegram backlog from being appended or replied again.
