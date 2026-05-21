# telegram-codex Agent Guide

## What This Skill Is For

Use `telegram-codex` when a Codex session needs to communicate through Telegram while keeping Dashboard in control of the polling lifecycle.

This skill gives Codex:

- Telegram update polling
- inbound text, photo, video, audio, voice, and document metadata
- Telegram file download by `file_id`
- outbound text reply
- outbound photo send
- outbound audio send
- outbound document send
- managed two-way Telegram communication through one DD collector per active workspace session

## Runtime Model

The always-on path is no longer a separate ad hoc listener command.

The managed path is:

```bash
dashboard telegram-codex.start
```

That command:

1. keeps the saved-session mapping logic from `TICKET_REF` and `~/.developer-dashboard/config/codex.json`
2. derives a collector session id from:
   - `TELEGRAM_CODEX_SESSION_ID`
   - `CODEX_SESSION_ID`
   - otherwise the workspace directory name
3. ensures there is exactly one collector named `telegram-codex-<session-id>` in `~/.developer-dashboard/config/config.json`
4. removes duplicates for that collector name
5. writes the actual Codex resume target into:

```bash
~/.telegram-codex/<session-id>/codex.session
```

6. restarts:

```bash
dashboard restart collector telegram-codex-<session-id>
```

7. launches the real Codex binary

When `~/.telegram-codex/<session-id>/codex.session` exists, the collector-owned `dashboard telegram-codex.check-message <session-id>` worker automatically resumes that Codex session to generate the Telegram reply text.

## Collector Contract

The collector shape is:

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

`dashboard telegram-codex.check-message <session-id>` is a long-running polling loop. Dashboard may try to start it every five seconds, but singleton mode plus the same-session pid guard prevents overlap while the active loop is still running. When `codex.session` exists for that session, the worker replies through that persisted Codex session automatically. If `listener.inbox.jsonl` proves a newer next offset than `listener.offset`, the worker rewrites `listener.offset` before polling so restart state stays accurate. While a managed Codex reply is being processed, the worker keeps Telegram `typing...` status active until the final outbound Telegram send attempt completes. Supported inbound media is downloaded into the session runtime before Codex replies, and Codex can return attachment directives to send photos, audio, or documents back to Telegram.

## What The Skill Can Receive

The skill can receive Telegram update metadata for:

- text
- photos
- video
- audio
- voice
- documents and other files

The polling loop records those inbound updates in:

```bash
~/.telegram-codex/<session-id>/listener.inbox.jsonl
```

Downloaded inbound media for managed replies is stored under:

```bash
~/.telegram-codex/<session-id>/downloads/
```

## What The Skill Can Read Versus Download

This skill reads Telegram update metadata directly.

For actual binary content, download first:

```bash
dashboard telegram-codex.download <FILE_ID>
```

That applies to:

- images
- video
- audio
- voice
- PDFs
- other Telegram-hosted files

The shipped `download` path and the managed collector-owned media reply path both use Telegram Bot API `getFile` query-string parameters correctly, so real Telegram photo and file downloads are expected to work in live runs.

Do not claim a binary attachment was read unless it was downloaded first.

## What The Skill Can Send Back

Text:

```bash
dashboard telegram-codex.reply <CHAT_ID> 'Message received'
```

Photo:

```bash
dashboard telegram-codex.send-photo <CHAT_ID> ~/Pictures/demo.png
```

Audio:

```bash
dashboard telegram-codex.send-audio <CHAT_ID> ~/Music/reply.mp3
```

Document:

```bash
dashboard telegram-codex.send-document <CHAT_ID> ~/Downloads/report.pdf
```

This skill does not currently expose dedicated outbound video sending.

## Key Commands

Install plugin bridge:

```bash
dashboard telegram-codex.install 123456:telegram-bot-token
```

Managed start:

```bash
dashboard telegram-codex.start
```

Collector loop:

```bash
dashboard telegram-codex.check-message <session-id>
```

Inspect updates:

```bash
dashboard telegram-codex.updates
```

Download file:

```bash
dashboard telegram-codex.download <FILE_ID>
```

Managed attachment reply directive:

```text
telegram_attachment_type=photo|audio|document
telegram_attachment_path=/absolute/local/path
telegram_attachment_caption=optional caption
```

## Important Rules For Another Codex Session

- Use `dashboard telegram-codex.start` when Telegram is meant to be the primary communication channel.
- Treat `dashboard telegram-codex.check-message <session-id>` as a collector-owned long-running loop, not as a short one-shot helper.
- Expect one DD collector per workspace session.
- Expect per-session state under `~/.telegram-codex/<session-id>/`.
- Do not claim outbound video sending support.
- Do not claim binary attachment content was inspected unless it was downloaded first.
