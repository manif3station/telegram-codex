# Initial Release

The first `telegram-codex` release adds a governed Telegram Bot API integration skill for Codex local plugin runtimes.

Included behavior:

- install or refresh the local `telegram-codex` plugin files
- poll Telegram updates for text, photos, and documents
- download Telegram files locally
- send replies, photos, and documents back to Telegram
- auto-reply to `/start`
- expose the same behavior through a generated stdio MCP server for Codex
- ship executable `./cli/*` entrypoints in the skill checkout so the local workflow is directly runnable before dashboard wiring
- prove the live Telegram flow against the real bot with install, bot lookup, update polling, `/start` auto-reply, and direct reply
