# telegram-codex

## Description

`telegram-codex` is a Developer Dashboard skill that installs and drives a local Codex Telegram MCP bridge.

## Value

It gives you a governed path to connect Telegram Bot API with Codex so you can poll messages, inspect photo or file metadata, download Telegram attachments locally, and send replies back to the same Telegram chat.

## Problem It Solves

Telegram bot experiments usually stop at an ad hoc token test or a one-off script. The Codex-side plugin files, marketplace entries, MCP server, and actual Telegram request flow drift apart quickly, which makes the bridge hard to reuse and hard to trust.

## What It Does To Solve It

The skill adds CLI commands that scaffold a local Codex plugin named `telegram-codex`, register it in the local Codex marketplace, and drive the same Telegram Bot API functions directly from the DD skill.

The skill repo also ships executable `./cli/*` entrypoints so the behavior can be proven directly from the skill checkout before it is wired into a broader `dashboard` install.

The installed plugin exposes a stdio MCP server with tools for:

- bot identity lookup
- polling inbound updates
- downloading Telegram files
- sending text replies
- sending photos
- sending documents
- auto-replying to `/start`

## Developer Dashboard Feature Added

This skill adds:

- `dashboard telegram-codex.install`
- `dashboard telegram-codex.get-me`
- `dashboard telegram-codex.updates`
- `dashboard telegram-codex.download`
- `dashboard telegram-codex.reply`
- `dashboard telegram-codex.send-photo`
- `dashboard telegram-codex.send-document`
- `dashboard telegram-codex.auto-reply-start`

## Installation

Install from the skill repo:

```bash
dashboard skills install ~/projects/skills/skills/telegram-codex
```

Then install the local Codex plugin bridge with a Telegram bot token:

```bash
dashboard telegram-codex.install 123456:telegram-bot-token
```

By default the skill writes the plugin bridge into:

- `~/.codex/.tmp/plugins/plugins/telegram-codex`
- `~/.codex/.tmp/plugins/.agents/plugins/marketplace.json`

If the mirror Codex runtime tree exists, the skill mirrors the same plugin into:

- `~/_codex/michael/.tmp/plugins/plugins/telegram-codex`
- `~/_codex/michael/.tmp/plugins/.agents/plugins/marketplace.json`

## CLI Usage

Run the local skill entrypoints directly from this repo:

```bash
cd ~/projects/skills/skills/telegram-codex
./cli/install 123456:telegram-bot-token
TELEGRAM_BOT_TOKEN=123456:telegram-bot-token ./cli/get-me
TELEGRAM_BOT_TOKEN=123456:telegram-bot-token ./cli/updates
TELEGRAM_BOT_TOKEN=123456:telegram-bot-token ./cli/auto-reply-start
```

Use the same behavior through the installed dashboard commands:

Install or refresh the local Codex Telegram plugin:

```bash
dashboard telegram-codex.install 123456:telegram-bot-token
```

Check the configured bot identity:

```bash
TELEGRAM_BOT_TOKEN=123456:telegram-bot-token dashboard telegram-codex.get-me
```

Poll recent Telegram updates:

```bash
TELEGRAM_BOT_TOKEN=123456:telegram-bot-token dashboard telegram-codex.updates
```

Download a Telegram file by `file_id`:

```bash
TELEGRAM_BOT_TOKEN=123456:telegram-bot-token dashboard telegram-codex.download AgACAgQAAxkBAAIB...
```

Reply to a Telegram chat:

```bash
TELEGRAM_BOT_TOKEN=123456:telegram-bot-token dashboard telegram-codex.reply 123456789 'Hello from Codex'
```

Send a local photo:

```bash
TELEGRAM_BOT_TOKEN=123456:telegram-bot-token dashboard telegram-codex.send-photo 123456789 ~/Pictures/demo.png
```

Send a local file:

```bash
TELEGRAM_BOT_TOKEN=123456:telegram-bot-token dashboard telegram-codex.send-document 123456789 ~/Downloads/report.pdf
```

Auto-reply to recent `/start` messages:

```bash
TELEGRAM_BOT_TOKEN=123456:telegram-bot-token dashboard telegram-codex.auto-reply-start
```

## Browser Usage

This skill does not add a browser interface.

## Normal Cases

```text
Use `dashboard telegram-codex.install` once per machine or whenever you want to refresh the local Codex Telegram plugin files.
```

```text
Use `dashboard telegram-codex.updates` after you send the bot a message or upload a file on Telegram.
```

```text
Use `dashboard telegram-codex.auto-reply-start` immediately after a new Telegram user sends `/start` if you want a fast bot-side readiness reply before a longer Codex workflow begins.
```

```text
Use `dashboard telegram-codex.reply`, `send-photo`, or `send-document` when you already know the target `chat_id`.
```

## Edge Cases

```text
If `TELEGRAM_BOT_TOKEN` is not set and no explicit install token is provided, the command fails instead of guessing a token source.
```

```text
If the local Codex marketplace file is missing, the install command creates it with a valid plugin entry for `telegram-codex`.
```

```text
If no Telegram updates are pending, `dashboard telegram-codex.updates` returns a zero-count result instead of failing.
```

```text
If `/start` has already been consumed from the Telegram update queue, `dashboard telegram-codex.auto-reply-start` returns zero replies and leaves the queue state unchanged.
```

## Docs

- `docs/overview.md`
- `docs/usage.md`
- `docs/changes/2026-05-20-initial-release.md`

## License

`telegram-codex` is released under the MIT License.

See [LICENSE](LICENSE).
