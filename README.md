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
2. derives one workspace session id for Telegram collector ownership from the workspace directory name unless `TELEGRAM_CODEX_SESSION_ID` was explicitly set
3. ensures there is exactly one collector named `telegram-codex-<session-id>` in `~/.developer-dashboard/config/config.json`
4. removes duplicate collector entries for that session if they exist and also removes stale same-workspace `telegram-codex-*` collectors that still point at the wrong session id
5. writes the active Codex reply target into `~/.telegram-codex/<session-id>/codex.session`
6. restarts the DD collector with:
   - `cwd` fixed to the workspace where `dashboard telegram-codex.start` was run
   - `command` fixed to `dashboard telegram-codex.check-message <session-id>`
   - `interval` fixed to `5`
   - `rotation.lines` fixed to `100`
   - `mode` fixed to `singleton`
7. launches the real Codex binary

`dashboard telegram-codex.start --version` is a pure metadata query that proxies the real underlying Codex CLI version output DD expects. DD can probe it safely without creating or restarting collectors.
Successful managed startup now hands off with `exec`, so the wrapper process does not stay resident as an extra long-lived `cli/start` parent after Codex takes over. Ambient workspace `OLLAMA_MODEL` is no longer treated as an automatic provider override for Telegram-managed startup. If Telegram-owned startup really needs the Ollama launch profile, set `TELEGRAM_CODEX_OLLAMA_MODEL` explicitly.

The collector-owned polling loop is now the always-on path. The old standalone listener command is no longer the primary runtime model.
When `codex.session` exists for that collector session, `dashboard telegram-codex.check-message <session-id>` automatically routes replies back through that saved Codex session.
If `codex.session` is missing, the managed reply path falls back to the same saved-session mapping in `~/.developer-dashboard/config/codex.json` that `telegram-codex.start` uses.

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
- downloaded Telegram photos and image documents are attached to resumed Codex replies as real `codex exec resume -i` image inputs
- the Codex prompt still receives `*_local_path=` lines for downloaded files, but non-image media remains a local-path input for tool-based inspection rather than a direct binary model attachment
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
While Codex is processing a managed reply, the worker keeps Telegram `typing...` status active through both reply generation and the final outbound Telegram send so the indicator does not disappear before the reply arrives.
For longer task-style Telegram requests, the worker also sends a separate in-progress status message while the resumed Codex session is still working, and removes that status message after the final substantive reply is delivered.
For inbound non-text updates, the worker downloads supported attachments into `~/.telegram-codex/<session-id>/downloads/` before asking Codex to reply. Downloaded Telegram photos and image documents are attached to the resumed Codex session as real image inputs. Other downloaded media still flows by local path for tool-based inspection. Codex can send a non-text reply back by returning directive lines:

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
- Do not claim audio, voice, video, or PDF bytes were attached directly to the model; today only downloaded Telegram photos and image documents are attached as real Codex image inputs.
- Do use `dashboard telegram-codex.start` for the real always-on path.
- Do treat `dashboard telegram-codex.check-message <session-id>` as a managed collector loop, not as a short one-off polling command.
- Do expect managed Telegram task replies to answer directly without boilerplate prefaces and to do the real in-session work before replying instead of sending a promise such as `will be done`.
- Do expect repeated nested `codex` calls inside one managed process tree to skip collector restarts because startup now carries a reentry guard.
