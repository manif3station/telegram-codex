# Usage

## Install The Skill

```bash
dashboard skills install telegram-codex
```

## Install The Local Codex Telegram Plugin

```bash
dashboard telegram-codex.install 123456:telegram-bot-token
```

That command writes the `telegram-codex` local plugin, the stdio MCP server config, the plugin-local `.env` with the bot token, and the marketplace entry that exposes the plugin to Codex.

Normal `dashboard skills install telegram-codex` also provisions:

- `~/.developer-dashboard/cli/codex` as a thin handoff launcher into `dashboard telegram-codex.start`
- a managed `codex` wrapper in the first supported user PATH directory, preferring `~/.local/bin/codex` and then `~/bin/codex`

The managed `codex` wrapper only hands off into `~/.developer-dashboard/cli/codex`. The real startup logic lives in `dashboard telegram-codex.start`.

After install, the regular commands can discover `TELEGRAM_BOT_TOKEN` automatically from the current project `.env`, a parent/root `.env`, the skill `.env`, or the live process environment.

The same behavior is available directly from the skill checkout:

```bash
cd ~/projects/skills/skills/telegram-codex
./cli/install 123456:telegram-bot-token
```

## Start Codex With Automatic Telegram Listener Startup

```bash
codex
```

Or run the skill-owned start path directly:

```bash
dashboard telegram-codex.start
```

`telegram-codex.start` starts one `telegram-codex` listener per Codex session when:

- `TELEGRAM_BOT_TOKEN` is available
- `TELEGRAM_CODEX_ENABLE_AUTOSTART=1`

On the first auto-start with no stored listener offset, it primes to the latest Telegram update and waits for new messages instead of replying to older backlog items.

It also preserves the original saved-session resume logic from `~/.developer-dashboard/config/codex.json` when `TICKET_REF` points to a stored Codex session id.

It records wrapper-managed listener state under:

- `~/.telegram-codex/<session-id>/listener.pid`
- `~/.telegram-codex/<session-id>/listener.log`
- `~/.telegram-codex/<session-id>/listener.offset`
- `~/.telegram-codex/<session-id>/listener.inbox.jsonl`

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

That command long-polls Telegram, appends inbound message summaries to `~/.telegram-codex/<session-id>/listener.inbox.jsonl`, and persists the next Telegram offset in `~/.telegram-codex/<session-id>/listener.offset`.
If `listener.offset` is missing but the inbox ledger exists, the listener recovers the next offset from the latest inbox entry and skips any returned update older than that recovered offset.

Session id resolution order is:

1. `TELEGRAM_CODEX_SESSION_ID`
2. `CODEX_SESSION_ID`
3. `default`

The listener sends an immediate text acknowledgement for inbound:

- text
- photos
- video
- audio
- voice
- documents/files

If Telegram rejects a reply, for example with a rate-limit error, the listener still advances the stored offset and records the reply failure instead of replaying the same inbound message forever on the next start.

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
