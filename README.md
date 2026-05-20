# telegram-codex

## Description

`telegram-codex` is a Developer Dashboard skill that installs and drives a local Codex Telegram MCP bridge.

## Value

It gives you a governed path to connect Telegram Bot API with Codex so you can poll messages, inspect text, photo, video, audio, voice, or file metadata, download Telegram attachments locally, and send replies back to the same Telegram chat.

It now also supports a long-poll listener mode so the bot can stay active and capture inbound Telegram activity without waiting for a manual Codex inbox check.

After `dashboard skills install telegram-codex`, the startup chain is:

- `codex`
- `~/.developer-dashboard/cli/codex`
- `dashboard telegram-codex.start`

The real Telegram-aware startup logic lives in `telegram-codex.start`, so the listener starts automatically for that Codex session while preserving the original saved-session resume behavior from `TICKET_REF` and `~/.developer-dashboard/config/codex.json`.
On the first auto-start with no stored offset, it primes to the latest Telegram update and does not auto-reply to old backlog messages.

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
- receiving text, photos, video, audio, voice, and documents through update metadata

The skill itself also exposes an always-on listener command that keeps a per-Codex-session Telegram inbox ledger and persistent update offset.
If the offset file is missing, the listener now recovers the next offset from the inbox ledger and skips stale returned updates older than that offset so old Telegram messages are not re-acknowledged again.
The listener is passive by default and does not send a placeholder bot reply unless you pass an explicit reply text on the command line.

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
- `dashboard telegram-codex.listen`
- `dashboard telegram-codex.start`

## Installation

Install from the skill repo:

```bash
dashboard skills install telegram-codex
```

Then install the local Codex plugin bridge with a Telegram bot token:

```bash
dashboard telegram-codex.install 123456:telegram-bot-token
```

Normal skill install also provisions:

- a thin `~/.developer-dashboard/cli/codex` launcher that hands off into `dashboard telegram-codex.start`
- a thin managed `codex` wrapper in the first supported user PATH directory, preferring:

- `~/.local/bin/codex`
- `~/bin/codex`

The managed wrapper hands off into `~/.developer-dashboard/cli/codex`, and `telegram-codex.start` then:

- preserves the original saved-session resume mapping from `TICKET_REF`
- starts the Telegram listener automatically when `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CODEX_ENABLE_AUTOSTART=1` are available
- keeps reply-send failures from replaying the same Telegram update forever by still advancing the stored offset
- execs the real Codex binary afterward

On the first auto-start with no stored offset, it primes to the latest Telegram update so old backlog messages are not auto-replied.

After install, regular commands can discover `TELEGRAM_BOT_TOKEN` automatically from:

- the active project `.env`
- a parent/root `.env`
- the skill-local `.env`
- the process environment

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
./cli/start
./cli/get-me
./cli/updates
./cli/auto-reply-start
./cli/listen
```

Use the same behavior through the installed dashboard commands:

Install or refresh the local Codex Telegram plugin:

```bash
dashboard telegram-codex.install 123456:telegram-bot-token
```

Check the configured bot identity:

```bash
dashboard telegram-codex.get-me
```

Poll recent Telegram updates:

```bash
dashboard telegram-codex.updates
```

Download a Telegram file by `file_id`:

```bash
dashboard telegram-codex.download AgACAgQAAxkBAAIB...
```

Reply to a Telegram chat:

```bash
dashboard telegram-codex.reply 123456789 'Hello from Codex'
```

Send a local photo:

```bash
dashboard telegram-codex.send-photo 123456789 ~/Pictures/demo.png
```

Send a local file:

```bash
dashboard telegram-codex.send-document 123456789 ~/Downloads/report.pdf
```

Auto-reply to recent `/start` messages:

```bash
dashboard telegram-codex.auto-reply-start
```

Run the always-on long-poll listener in the foreground:

```bash
dashboard telegram-codex.listen
```

Run the listener with an explicit acknowledgement reply only when you really want one:

```bash
dashboard telegram-codex.listen 0 30 'Message received'
```

Launch Codex with automatic Telegram listener startup:

```bash
codex
```

Run the skill-owned startup flow directly:

```bash
dashboard telegram-codex.start
```

By default the listener keeps runtime state under:

- `~/.telegram-codex/<codex-session-id>/listener.offset`
- `~/.telegram-codex/<codex-session-id>/listener.inbox.jsonl`
- `~/.telegram-codex/<codex-session-id>/listener.pid`
- `~/.telegram-codex/<codex-session-id>/listener.log`

Session id resolution order is:

1. `TELEGRAM_CODEX_SESSION_ID`
2. `CODEX_SESSION_ID`
3. `default`

Run it continuously in the background from the skill checkout:

```bash
cd ~/projects/skills/skills/telegram-codex
nohup ./cli/listen >/tmp/telegram-codex-listener.log 2>&1 &
```

## Browser Usage

This skill does not add a browser interface.

## Normal Cases

```text
Use `dashboard telegram-codex.install` once per machine or whenever you want to refresh the local Codex Telegram plugin files. Normal `dashboard skills install telegram-codex` already provisions the managed `codex` wrapper.
```

```text
Use `dashboard telegram-codex.updates` after you send the bot a message or upload a file on Telegram.
```

```text
Use `dashboard telegram-codex.auto-reply-start` immediately after a new Telegram user sends `/start` if you want a fast explicit bot-side readiness reply before a longer Codex workflow begins.
```

```text
Use `dashboard telegram-codex.reply`, `send-photo`, or `send-document` when you already know the target `chat_id`.
```

```text
Use `dashboard telegram-codex.listen` when you want immediate bot acknowledgements without manually polling `updates` from an active Codex session, while keeping that session's Telegram history separate from other Codex sessions.
```

```text
Use `codex` after `dashboard skills install telegram-codex` when you want the thin launcher chain to reach `dashboard telegram-codex.start`, preserve any saved ticket-to-session mapping, and bring the Telegram listener up automatically for the current session.
```

```text
On the first managed `codex` auto-start with no stored listener offset, the listener primes itself to the latest Telegram update and waits for new messages instead of replying to older backlog items.
```

```text
Use `dashboard telegram-codex.download <FILE_ID>` after an inbound photo, video, audio, voice, or document update when Codex needs the actual file content rather than just Telegram metadata.
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

```text
If you restart `dashboard telegram-codex.listen` inside the same Codex session id, it resumes from that session's stored listener offset instead of reprocessing old Telegram updates.
```

```text
If your shell resolves `codex` to some other binary before `~/.local/bin` or `~/bin`, the listener will not auto-start for that session until your PATH order is corrected.
```

## Agent Handoff

- `AGENT.SKILL.md`

## Docs

- `docs/overview.md`
- `docs/usage.md`
- `docs/changes/2026-05-20-initial-release.md`
- `docs/changes/2026-05-20-codex-command-wrapper-autostart.md`
- `docs/changes/2026-05-20-no-backlog-autostart-priming.md`

## License

`telegram-codex` is released under the MIT License.

See [LICENSE](LICENSE).
