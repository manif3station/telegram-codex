# EPIC-271

## Summary

Add a governed `telegram-codex` skill that bridges Telegram Bot API into a local Codex plugin and stdio MCP server, then extend it with DD-collector-owned always-on polling, per-session runtime state, a managed `codex` launcher path that starts the Telegram collector automatically while preserving the original saved-session resume flow, replay guards that stop stale Telegram backlog from being appended or replied again, managed Telegram typing indicators while Codex is generating replies, managed inbound/outbound media handling through downloaded local files plus attachment reply directives, and a verified `getFile` query-string path so real inbound Telegram media downloads work in live collector flows.
