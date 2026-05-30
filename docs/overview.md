# Overview

`telegram-codex` packages a Telegram Bot API bridge as a governed DD skill. The skill owns two things:

1. a Perl command surface for install, poll, download, reply, and always-on listener flows
2. a generated local Codex plugin with a stdio MCP server

The skill is aimed at a personal local Codex runtime where plugin files live under `~/.codex/.tmp/plugins/` and, when present, a mirrored runtime under `~/_codex/michael/.tmp/plugins/`.

For the managed startup path, `dashboard telegram-codex.start` now keeps collector ownership tied to the workspace directory name unless `TELEGRAM_CODEX_SESSION_ID` was explicitly set. It intentionally ignores ambient workspace `CODEX_SESSION_ID` and `OLLAMA_MODEL` so nested Codex chains or unrelated workspace provider env do not create the wrong collector session or recurse through a wrapped Ollama launch path.

For the listener path, the skill keeps runtime state under `~/.telegram-codex/<session-id>/` by default:

- `listener.offset`
- `listener.inbox.jsonl`

Session id resolution order is:

1. `TELEGRAM_CODEX_SESSION_ID`
2. `CODEX_SESSION_ID`
3. `default`

Inbound update support covers:

- text
- photos
- video
- audio
- voice
- documents and files

Outbound send support currently covers:

- text replies
- photos
- audio
- documents

Managed media understanding currently splits into two paths:

- downloaded Telegram photos and image documents are attached to resumed Codex replies as real image inputs
- audio, voice, video, PDFs, and other non-image files are downloaded locally and exposed by path for tool-based inspection, not direct binary model attachment

Managed reply progress now uses a third path:

- Telegram sees a preserved in-chat verbose trace built from real `codex exec resume --json` agent and command events instead of a generic progress heartbeat
- live tmux-backed Telegram injection now uses the Codex composer submit keystroke, so pasted Telegram turns are committed into the TUI instead of being left in the prompt buffer
- shared-transcript mirroring is serviced before each Telegram poll cycle, so TUI-originated outbound mirroring is not blocked behind a transient `getUpdates` failure
