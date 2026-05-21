# Real Image Input Handoff For Managed Telegram Replies

## Summary

Managed `telegram-codex` replies now attach downloaded Telegram photos and image documents to resumed Codex sessions as real `codex exec resume -i` image inputs instead of only describing those files by local path in prompt text.

## What Changed

- `dashboard telegram-codex.check-message <session-id>` still downloads supported Telegram media into `~/.telegram-codex/<session-id>/downloads/`
- downloaded Telegram photos are now attached to `codex exec resume` as real image inputs
- downloaded Telegram image documents are also attached as real image inputs when their MIME type or filename proves they are images
- audio, voice, video, PDF, and other non-image files still flow through downloaded local paths for tool-based inspection, not direct binary model attachment
- the managed reply prompt now tells Codex which part of the media contract is real image attachment and which part is local-path-only

## Verification

- Docker functional gate passed at `Files=6, Tests=405`
- Docker covered gate passed at `Files=6, Tests=405`
- `lib/Telegram/Codex/Manager.pm` kept `100.0%` statement and `100.0%` subroutine coverage
