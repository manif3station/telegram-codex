# Overview

`telegram-codex` packages a Telegram Bot API bridge as a governed DD skill. The skill owns two things:

1. a Perl command surface for install, poll, download, reply, and always-on listener flows
2. a generated local Codex plugin with a stdio MCP server

The skill is aimed at a personal local Codex runtime where plugin files live under `~/.codex/.tmp/plugins/` and, when present, a mirrored runtime under `~/_codex/michael/.tmp/plugins/`.

For the listener path, the skill keeps runtime state under `~/.telegram-codex/` by default:

- `listener.offset`
- `listener.inbox.jsonl`

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
- documents
