# Managed Telegram Media Download And Attachment Replies

## Summary

The managed collector-owned Telegram reply path now downloads inbound supported media into the session runtime before Codex replies, exposes those local paths in the Codex prompt, and supports outbound attachment directives for photo, audio, and document replies.

## Why

Metadata alone was not enough for real media conversations. Codex needed a local file path to inspect the inbound attachment, and the managed reply path needed a governed way to send files back to Telegram instead of only plain text.

## Result

- inbound photo, document, audio, video, and voice files are downloaded into `~/.telegram-codex/<session-id>/downloads/`
- the reply prompt includes `*_local_path=` lines and explicitly says those files are already local
- managed Codex replies can now send photo, audio, and document attachments back to Telegram by returning:
  - `telegram_attachment_type=photo|audio|document`
  - `telegram_attachment_path=/absolute/local/path`
  - `telegram_attachment_caption=optional caption`
- the public command surface now includes `dashboard telegram-codex.send-audio`

## Verification

- Docker functional gate passed at `Files=6, Tests=321`
- Docker covered gate passed with `lib/Telegram/Codex/Manager.pm` statement `100.0`
- Docker covered gate passed with `lib/Telegram/Codex/Manager.pm` subroutine `100.0`
