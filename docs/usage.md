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
After that first prime step, managed startup routes each new inbound Telegram text message through the active Codex session by resuming that session and asking Codex to generate the Telegram reply text within the live session context.
Managed startup now launches the skill-owned `cli/listen` directly, so `listener.pid` follows the real resident listener process instead of an intermediate wrapper process.

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
If the stored offset is older than the inbox-ledger offset, the listener now advances to the newer inbox-ledger offset instead of replaying duplicated older Telegram updates.
Passing `0` as `MAX_CYCLES` means "stay running forever" instead of "stop after one cycle."
By default it does not send a Telegram reply. It only captures inbound activity unless you pass an explicit reply text.
Managed startup uses a different mode than direct `listen`: it resumes the active Codex session to generate Telegram replies instead of relying on a static reply string.

Session id resolution order is:

1. `TELEGRAM_CODEX_SESSION_ID`
2. `CODEX_SESSION_ID`
3. `default`

When you pass an explicit reply text, the listener can send an acknowledgement for inbound:

- text
- photos
- video
- audio
- voice
- documents/files

If Telegram rejects a reply, for example with a rate-limit error, the listener still advances the stored offset and records the reply failure instead of replaying the same inbound message forever on the next start.
If Telegram `getUpdates` hits a transient transport failure, the listener records the error, pauses briefly, and continues listening instead of exiting immediately.

For a passive one-cycle check:

```bash
./cli/listen 1 0
```

For an explicit acknowledgement reply:

```bash
./cli/listen 1 0 'Message received'
```

For an explicit acknowledgement reply that should keep running:

```bash
./cli/listen 0 30 'Message received'
```

For a background listener from the skill checkout:

```bash
cd ~/projects/skills/skills/telegram-codex
nohup ./cli/listen >/tmp/telegram-codex-listener.log 2>&1 &
```

## Agent Handoff

Another Codex session can use [AGENT.SKILL.md](../AGENT.SKILL.md) as the skill handoff guide.
