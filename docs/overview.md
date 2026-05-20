# Overview

`telegram-codex` packages a Telegram Bot API bridge as a governed DD skill. The skill owns two things:

1. a Perl command surface for install, poll, download, and reply flows
2. a generated local Codex plugin with a stdio MCP server

The skill is aimed at a personal local Codex runtime where plugin files live under `~/.codex/.tmp/plugins/` and, when present, a mirrored runtime under `~/_codex/michael/.tmp/plugins/`.
