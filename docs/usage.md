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
   - otherwise the workspace directory name
3. ensures there is exactly one `telegram-codex-<session-id>` collector in `~/.developer-dashboard/config/config.json`
4. removes duplicates for that same collector name and heals stale same-workspace `telegram-codex-*` entries that still point at the wrong session id
5. writes the active Codex resume target to `~/.telegram-codex/<session-id>/codex.session`
6. runs:

```bash
dashboard restart collector telegram-codex-<session-id>
```

7. launches the real Codex binary

`dashboard telegram-codex.start --version` is intentionally side-effect free and proxies the real Codex CLI version output DD launcher checks expect, so DD command-family discovery can probe it without touching collectors.
On a real startup, the launcher now uses `exec` for real Codex handoff, so a successful run does not leave an extra resident `cli/start` wrapper process behind.
Ambient workspace `OLLAMA_MODEL` is ignored by Telegram-managed startup. If you intentionally want Telegram-managed startup to inject the Ollama launch profile, set `TELEGRAM_CODEX_OLLAMA_MODEL` explicitly.

If `codex.session` is missing later, the managed reply path falls back to the same saved-session mapping in `~/.developer-dashboard/config/codex.json` instead of blindly using the collector session id.

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

Dashboard may try to schedule it every five seconds, but singleton mode plus the same-session pid guard prevents a second `check-message <session-id>` copy from starting while the existing loop is still running. If `~/.telegram-codex/<session-id>/codex.session` exists, the worker automatically resumes that Codex session to generate the Telegram reply. If that file is missing, the worker falls back to the saved-session mapping in `~/.developer-dashboard/config/codex.json`. If `listener.inbox.jsonl` proves a newer next offset than `listener.offset`, the worker rewrites `listener.offset` before polling so restart state and replay diagnostics stay aligned. While that managed reply is being processed, the worker keeps Telegram `typing...` status active until the final outbound Telegram send attempt completes. For longer task-style requests, it also sends a separate in-progress status message while the resumed Codex session is still working.
Before that managed reply is generated, supported inbound Telegram media is downloaded into the session runtime and exposed to Codex through `*_local_path=` lines in the reply prompt.
Managed task replies also tell Codex to answer directly without boilerplate prefaces and to do the actual work before replying instead of returning promise-only placeholders such as `will be done`.
Nested managed `codex` invocations inside the same process tree inherit a startup reentry guard, so they do not keep re-running collector restart side effects.

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

The managed `check-message` loop now performs that download step automatically for inbound supported media before Codex replies.
The direct `download` command and the managed collector-owned media path both use Telegram Bot API `getFile` query-string parameters correctly, so real inbound Telegram photo and file downloads work in live runs.

## Send Replies

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

Managed Codex replies can also send those files back automatically by returning:

```text
telegram_attachment_type=photo|audio|document
telegram_attachment_path=/absolute/local/path
telegram_attachment_caption=optional caption
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
- `~/.telegram-codex/<session-id>/downloads/`

`listener.offset` keeps the next Telegram update offset and is healed immediately from the inbox ledger when inbox recovery proves a newer next offset.

`listener.inbox.jsonl` keeps the per-session inbound update ledger.

`codex.session` keeps the real Codex session that the collector-owned `check-message <session-id>` worker resumes to generate Telegram replies.
`downloads/` keeps inbound supported Telegram media that was downloaded for Codex before reply generation.

## Media Handling Rule

`telegram-codex` can receive and route metadata for text, images, video, audio, voice, PDFs, and other files.

It must not claim that a binary attachment was read just because the update metadata arrived. Download the file by `file_id` first when the content itself matters.
