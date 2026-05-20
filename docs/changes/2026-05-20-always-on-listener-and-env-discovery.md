# Always-On Listener And `.env` Discovery

`telegram-codex` now includes a long-poll listener path through `dashboard telegram-codex.listen` and `./cli/listen`.

Included behavior:

- keep an always-on Telegram listener running in the foreground or under `nohup`
- persist the next Telegram update offset in `~/.telegram-codex/listener.offset`
- append inbound Telegram message summaries to `~/.telegram-codex/listener.inbox.jsonl`
- send immediate listener replies for inbound text, photo, video, audio, voice, and document/file messages
- discover `TELEGRAM_BOT_TOKEN` from the active project `.env`, parent/root `.env`, skill `.env`, or process environment
