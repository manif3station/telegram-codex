# telegram-codex

## Description

`telegram-codex` is a Developer Dashboard skill that bridges Telegram Bot API into Codex and keeps two-way Telegram communication attached to one active Codex session through the DD collector runtime.

## What It Solves

Most Telegram bot experiments stop at one-off scripts. They do not stay aligned with:

- Codex startup
- Dashboard runtime management
- repeatable PM/test/release gates
- session-specific conversation state

`telegram-codex` solves that by making Dashboard own the Telegram polling lifecycle.

## Current Runtime Model

After:

```bash
dashboard skills install telegram-codex
```

the managed startup chain is:

- `codex`
- `~/.developer-dashboard/cli/codex`
- `dashboard telegram-codex.start`

When `dashboard telegram-codex.start` runs with `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CODEX_ENABLE_AUTOSTART=1`, it:

1. preserves the saved-session resume logic from `TICKET_REF` and `~/.developer-dashboard/config/codex.json`
2. derives one workspace session id for Telegram collector ownership
3. ensures there is exactly one collector named `telegram-codex-<session-id>` in `~/.developer-dashboard/config/config.json`
4. removes duplicate collector entries for that session if they exist
5. writes the active Codex reply target into `~/.telegram-codex/<session-id>/codex.session`
6. restarts the DD collector with:
   - `cwd` fixed to the workspace where `dashboard telegram-codex.start` was run
   - `command` fixed to `dashboard telegram-codex.check-message <session-id>`
   - `interval` fixed to `5`
   - `rotation.lines` fixed to `100`
   - `mode` fixed to `singleton`
7. launches the real Codex binary

The collector-owned polling loop is now the always-on path. The old standalone listener command is no longer the primary runtime model.
When `codex.session` exists for that collector session, `dashboard telegram-codex.check-message <session-id>` automatically routes replies back through that saved Codex session.

## What The Skill Supports

Inbound Telegram update metadata:

- text
- photos
- videos
- audio
- voice
- documents and other files

Outbound Telegram actions:

- text replies
- local photo sends
- local audio sends
- local document sends

Attachment handling:

- metadata is available directly in updates and collector processing
- managed `dashboard telegram-codex.check-message <session-id>` now downloads inbound supported media into the session runtime before Codex replies
- the Codex prompt receives `*_local_path=` lines for those downloaded files
- direct `dashboard telegram-codex.download <FILE_ID>` and managed inbound-media downloads now use Telegram Bot API `getFile` query-string parameters correctly, so real photo and file downloads work in live runs

## Commands

Install or refresh the local Codex plugin bridge:

```bash
dashboard telegram-codex.install 123456:telegram-bot-token
```

Start the managed Codex + collector path:

```bash
dashboard telegram-codex.start
```

Run the collector-owned polling loop directly for debugging:

```bash
dashboard telegram-codex.check-message <session-id>
```

Inspect the bot identity:

```bash
dashboard telegram-codex.get-me
```

Inspect recent Telegram updates:

```bash
dashboard telegram-codex.updates
```

Download an inbound Telegram file by `file_id`:

```bash
dashboard telegram-codex.download <FILE_ID>
```

Send a text reply:

```bash
dashboard telegram-codex.reply <CHAT_ID> 'Hello from Codex'
```

Send a photo:

```bash
dashboard telegram-codex.send-photo <CHAT_ID> ~/Pictures/demo.png
```

Send audio:

```bash
dashboard telegram-codex.send-audio <CHAT_ID> ~/Music/reply.mp3
```

Send a document:

```bash
dashboard telegram-codex.send-document <CHAT_ID> ~/Downloads/report.pdf
```

Reply to pending `/start` messages:

```bash
dashboard telegram-codex.auto-reply-start
```

## Collector Contract

The collector record created or healed by `dashboard telegram-codex.start` looks like this:

```json
{
  "name": "telegram-codex-<session-id>",
  "interval": 5,
  "rotation": { "lines": 100 },
  "cwd": "<workspace where start was run>",
  "command": "dashboard telegram-codex.check-message <session-id>",
  "mode": "singleton"
}
```

`dashboard telegram-codex.check-message <session-id>` is a long-running polling loop. Dashboard attempts to schedule it every five seconds, but singleton mode plus the same-session pid guard prevents overlap while the existing loop is still alive. When `~/.telegram-codex/<session-id>/codex.session` exists, the worker resumes that Codex session to generate the Telegram reply text. If `listener.offset` is missing or stale but `listener.inbox.jsonl` proves a newer next offset, the worker rewrites `listener.offset` to that recovered value before polling so restart state stays truthful.
While Codex is generating a managed reply, the worker also sends Telegram `typing...` status so the user can see the message is being processed.
For inbound non-text updates, the worker downloads supported attachments into `~/.telegram-codex/<session-id>/downloads/` before asking Codex to reply. Codex can send a non-text reply back by returning directive lines:

```text
telegram_attachment_type=photo|audio|document
telegram_attachment_path=/absolute/local/path
telegram_attachment_caption=optional caption
```

Stop it with Dashboard collector lifecycle commands, for example:

```bash
dashboard stop collector telegram-codex-<session-id>
```

## Session State

The skill keeps per-session Telegram state under:

- `~/.telegram-codex/<session-id>/listener.offset`
- `~/.telegram-codex/<session-id>/listener.inbox.jsonl`
- `~/.telegram-codex/<session-id>/codex.session`
- `~/.telegram-codex/<session-id>/downloads/`

`codex.session` stores the actual Codex session that Telegram replies should resume. That target may be different from the collector session name when `TICKET_REF` maps the workspace to a saved Codex session.
`listener.offset` is healed from `listener.inbox.jsonl` immediately when inbox-ledger recovery proves a newer next offset.
`downloads/` stores inbound media that the managed collector downloaded for Codex inspection before reply generation.

## Important Rules

- Do not claim binary media content was read unless the file was downloaded first.
- Do not claim outbound video send support; text, photo, audio, and document sending are implemented.
- Do use `dashboard telegram-codex.start` for the real always-on path.
- Do treat `dashboard telegram-codex.check-message <session-id>` as a managed collector loop, not as a short one-off polling command.
