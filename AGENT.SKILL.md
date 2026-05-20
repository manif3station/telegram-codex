# telegram-codex Agent Guide

## What This Skill Is For

`telegram-codex` gives a Codex session a governed Telegram Bot API bridge.

Use it when a Codex session needs to:

- receive Telegram updates
- inspect inbound text, photos, video, audio, voice, and document metadata
- download Telegram-hosted files locally by `file_id`
- send a text reply back to the same chat
- send a local photo back to Telegram
- send a local file back to Telegram as a document
- keep an always-on long-poll listener running for immediate acknowledgements
- start Codex through the thin launcher chain that reaches `dashboard telegram-codex.start` and brings the listener up automatically for that session

## Token Discovery

`TELEGRAM_BOT_TOKEN` is discovered in this order:

1. process environment
2. current project `.env`
3. parent or root `.env`
4. skill-level `.env`

So `dashboard telegram-codex...` or `./cli/...` does not require an explicit export when one of those `.env` files already provides the token.

## What The Skill Can Receive

The skill can receive Telegram update metadata for:

- text messages
- photos
- videos
- audio
- voice messages
- documents and other files

The listener and polling commands log these inbound updates into a local inbox ledger.

## What The Skill Can Read Versus Download

This skill reads inbound Telegram update metadata directly.

For file content:

- photos: receive metadata in updates, then download with `dashboard telegram-codex.download <FILE_ID>`
- videos: receive metadata in updates, then download with `dashboard telegram-codex.download <FILE_ID>`
- audio: receive metadata in updates, then download with `dashboard telegram-codex.download <FILE_ID>`
- voice: receive metadata in updates, then download with `dashboard telegram-codex.download <FILE_ID>`
- documents/files: receive metadata in updates, then download with `dashboard telegram-codex.download <FILE_ID>`

So another Codex session should not claim it can directly inspect the binary content of an inbound media message until it has downloaded the file by `file_id`.

## What The Skill Can Send Back

The skill can send back:

- text replies with `dashboard telegram-codex.reply`
- local photos with `dashboard telegram-codex.send-photo`
- local files as documents with `dashboard telegram-codex.send-document`

This skill does not currently expose dedicated `send-audio` or `send-video` commands.

## Core Commands

Install or refresh the local Codex plugin bridge:

```bash
dashboard telegram-codex.install 123456:telegram-bot-token
```

Read bot identity:

```bash
dashboard telegram-codex.get-me
```

Poll inbound Telegram updates:

```bash
dashboard telegram-codex.updates
```

Download an inbound file by `file_id`:

```bash
dashboard telegram-codex.download <FILE_ID>
```

Reply with text:

```bash
dashboard telegram-codex.reply <CHAT_ID> 'Message received'
```

Send a photo:

```bash
dashboard telegram-codex.send-photo <CHAT_ID> ~/Pictures/demo.png
```

Send a document:

```bash
dashboard telegram-codex.send-document <CHAT_ID> ~/Downloads/report.pdf
```

Reply to pending `/start` messages:

```bash
dashboard telegram-codex.auto-reply-start
```

Run the always-on listener:

```bash
dashboard telegram-codex.listen
```

Launch Codex with listener auto-start:

```bash
codex
```

Run the skill-owned start path directly:

```bash
dashboard telegram-codex.start
```

## Listener Behavior

`dashboard telegram-codex.listen` or `./cli/listen`:

- long-polls Telegram continuously
- persists the next Telegram update offset
- writes inbound update summaries to `~/.telegram-codex/<session-id>/listener.inbox.jsonl`
- keeps offset state in `~/.telegram-codex/<session-id>/listener.offset`
- resolves the session id in this order:
  - `TELEGRAM_CODEX_SESSION_ID`
  - `CODEX_SESSION_ID`
  - `default`
- recovers the next offset from the inbox ledger when `listener.offset` is missing
- skips any returned update older than the next stored offset so stale Telegram backlog is not re-acknowledged again
- does not send any Telegram reply by default
- sends an acknowledgement for inbound only when an explicit reply text is passed:
  - text
  - photos
  - videos
  - audio
  - voice
  - documents/files

The managed startup chain:

- `codex`
- `~/.developer-dashboard/cli/codex`
- `dashboard telegram-codex.start`

The real startup logic in `telegram-codex.start`:

- preserves the original saved-session resume mapping from `TICKET_REF` and `~/.developer-dashboard/config/codex.json`
- starts the listener automatically before Codex launches
- keeps one listener per session id
- persists wrapper-managed pid and log files under `~/.telegram-codex/<session-id>/`
- primes to the latest Telegram update on the first auto-start when no stored offset exists, so old backlog messages are not auto-replied
- still advances the stored offset when a reply send fails, so one bad Telegram acknowledgement does not cause repeated message spam

## Running The Listener

Foreground:

```bash
dashboard telegram-codex.listen
```

From the skill checkout:

```bash
cd ~/projects/skills/skills/telegram-codex
./cli/listen
```

Background example:

```bash
cd ~/projects/skills/skills/telegram-codex
nohup ./cli/listen >/tmp/telegram-codex-listener.log 2>&1 &
```

## Important Usage Rules For Another Codex Session

- Do not claim binary media content has been inspected unless the file was downloaded first.
- Do not claim audio or video sending support; only text, photo, and document sending are implemented.
- Do use the listener for passive inbox capture by default.
- Do pass an explicit reply text only when an acknowledgement message is truly wanted.
- Do use a stable `CODEX_SESSION_ID` or `TELEGRAM_CODEX_SESSION_ID` when you want a later Codex session to resume the same Telegram conversation history cleanly.
- Do launch Codex through the managed `codex` command path, or call `dashboard telegram-codex.start` directly, when Telegram is meant to be the primary communication channel.
- Do expect the first managed auto-start to ignore stale backlog messages and only auto-reply to new inbound messages after the listener offset is primed.
- Do stop the listener if automatic replies become noisy or unwanted.
