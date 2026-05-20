# Usage

## Install The Skill

```bash
dashboard skills install telegram-codex
```

## Install The Local Codex Telegram Plugin

```bash
dashboard telegram-codex.install 123456:telegram-bot-token
```

That command writes the local Codex plugin, the stdio MCP config, the plugin-local `.env`, and the marketplace entry used by Codex.

## Start The Managed Telegram Runtime

Use:

```bash
dashboard telegram-codex.start
```

or launch Codex normally through the managed wrapper:

```bash
codex
```

With `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CODEX_ENABLE_AUTOSTART=1`, `telegram-codex.start` now does this:

1. loads the saved Codex-session mapping from `~/.developer-dashboard/config/codex.json` when `TICKET_REF` points to one
2. derives a stable Telegram collector session id from:
   - `TELEGRAM_CODEX_SESSION_ID`
   - `CODEX_SESSION_ID`
   - otherwise the workspace directory name
3. ensures there is exactly one `telegram-codex-<session-id>` collector in `~/.developer-dashboard/config/config.json`
4. removes duplicates for that same collector name
5. writes the active Codex resume target to `~/.telegram-codex/<session-id>/codex.session`
6. runs:

```bash
dashboard restart collector telegram-codex-<session-id>
```

7. launches the real Codex binary

## Collector-Owned Polling Loop

The collector command is:

```bash
dashboard telegram-codex.check-message <session-id>
```

This is a long-running polling loop, not a short one-shot helper.

The collector definition installed or healed by `telegram-codex.start` is:

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

Dashboard may try to schedule it every five seconds, but singleton mode plus the same-session pid guard prevents a second `check-message <session-id>` copy from starting while the existing loop is still running. If `~/.telegram-codex/<session-id>/codex.session` exists, the worker automatically resumes that Codex session to generate the Telegram reply.

Stop it with Dashboard:

```bash
dashboard stop collector telegram-codex-<session-id>
```

## Poll Updates Directly

```bash
dashboard telegram-codex.updates
```

That update payload can include metadata for:

- text
- photos
- video
- audio
- voice
- documents/files

## Download Inbound Media

```bash
dashboard telegram-codex.download <FILE_ID>
```

Use that for photos, videos, audio, voice, PDFs, and other Telegram-hosted files whenever the actual content must be inspected.

## Send Replies

Text:

```bash
dashboard telegram-codex.reply <CHAT_ID> 'Message received'
```

Photo:

```bash
dashboard telegram-codex.send-photo <CHAT_ID> ~/Pictures/demo.png
```

Document:

```bash
dashboard telegram-codex.send-document <CHAT_ID> ~/Downloads/report.pdf
```

## `/start` Acknowledgement Helper

```bash
dashboard telegram-codex.auto-reply-start
```

## Session Runtime Files

Per-session runtime state lives under:

- `~/.telegram-codex/<session-id>/listener.offset`
- `~/.telegram-codex/<session-id>/listener.inbox.jsonl`
- `~/.telegram-codex/<session-id>/codex.session`

`listener.offset` keeps the next Telegram update offset.

`listener.inbox.jsonl` keeps the per-session inbound update ledger.

`codex.session` keeps the real Codex session that the collector-owned `check-message <session-id>` worker resumes to generate Telegram replies.

## Media Handling Rule

`telegram-codex` can receive and route metadata for text, images, video, audio, voice, PDFs, and other files.

It must not claim that a binary attachment was read just because the update metadata arrived. Download the file by `file_id` first when the content itself matters.
