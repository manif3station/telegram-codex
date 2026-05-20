# Usage

## Install The Skill

```bash
dashboard skills install ~/projects/skills/skills/telegram-codex
```

## Install The Local Codex Telegram Plugin

```bash
dashboard telegram-codex.install 123456:telegram-bot-token
```

That command writes the `telegram-codex` local plugin, the stdio MCP server config, the plugin-local `.env` with the bot token, and the marketplace entry that exposes the plugin to Codex.

After install, the regular commands can discover `TELEGRAM_BOT_TOKEN` automatically from the current project `.env`, a parent/root `.env`, the skill `.env`, or the live process environment.

The same behavior is available directly from the skill checkout:

```bash
cd ~/projects/skills/skills/telegram-codex
./cli/install 123456:telegram-bot-token
```

## Inspect The Bot Identity

```bash
dashboard telegram-codex.get-me
```

```bash
./cli/get-me
```

## Poll Messages, Photos, And Files

```bash
dashboard telegram-codex.updates
```

```bash
./cli/updates 0 10 0
```

That update payload can include metadata for:

- text
- photos
- video
- audio
- voice
- documents/files

## Download A Telegram File

```bash
dashboard telegram-codex.download AgACAgQAAxkBAAIB...
```

Use that command for any inbound Telegram media that exposes a `file_id`, including photos, video, audio, voice, and documents.

## Reply Back To Telegram

```bash
dashboard telegram-codex.reply 123456789 'Message received'
```

## Send A Photo

```bash
dashboard telegram-codex.send-photo 123456789 ~/Pictures/demo.png
```

## Send A Document

```bash
dashboard telegram-codex.send-document 123456789 ~/Downloads/report.pdf
```

## Auto Reply To `/start`

```bash
dashboard telegram-codex.auto-reply-start
```

```bash
./cli/auto-reply-start
```

## Run The Always-On Listener

```bash
dashboard telegram-codex.listen
```

That command long-polls Telegram, appends inbound message summaries to `~/.telegram-codex/listener.inbox.jsonl`, and persists the next Telegram offset in `~/.telegram-codex/listener.offset`.

The listener sends an immediate text acknowledgement for inbound:

- text
- photos
- video
- audio
- voice
- documents/files

For a controlled one-cycle check:

```bash
./cli/listen 1 0 'telegram-codex listener is live'
```

For a background listener from the skill checkout:

```bash
cd ~/projects/skills/skills/telegram-codex
nohup ./cli/listen >/tmp/telegram-codex-listener.log 2>&1 &
```

## Agent Handoff

Another Codex session can use [AGENT.SKILL.md](../AGENT.SKILL.md) as the skill handoff guide.
