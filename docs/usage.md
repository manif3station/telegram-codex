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

The same behavior is available directly from the skill checkout:

```bash
cd ~/projects/skills/skills/telegram-codex
./cli/install 123456:telegram-bot-token
```

## Inspect The Bot Identity

```bash
TELEGRAM_BOT_TOKEN=123456:telegram-bot-token dashboard telegram-codex.get-me
```

```bash
TELEGRAM_BOT_TOKEN=123456:telegram-bot-token ./cli/get-me
```

## Poll Messages, Photos, And Files

```bash
TELEGRAM_BOT_TOKEN=123456:telegram-bot-token dashboard telegram-codex.updates
```

```bash
TELEGRAM_BOT_TOKEN=123456:telegram-bot-token ./cli/updates 0 10 0
```

## Download A Telegram File

```bash
TELEGRAM_BOT_TOKEN=123456:telegram-bot-token dashboard telegram-codex.download AgACAgQAAxkBAAIB...
```

## Reply Back To Telegram

```bash
TELEGRAM_BOT_TOKEN=123456:telegram-bot-token dashboard telegram-codex.reply 123456789 'Message received'
```

## Send A Photo

```bash
TELEGRAM_BOT_TOKEN=123456:telegram-bot-token dashboard telegram-codex.send-photo 123456789 ~/Pictures/demo.png
```

## Send A Document

```bash
TELEGRAM_BOT_TOKEN=123456:telegram-bot-token dashboard telegram-codex.send-document 123456789 ~/Downloads/report.pdf
```

## Auto Reply To `/start`

```bash
TELEGRAM_BOT_TOKEN=123456:telegram-bot-token dashboard telegram-codex.auto-reply-start
```

```bash
TELEGRAM_BOT_TOKEN=123456:telegram-bot-token ./cli/auto-reply-start
```
