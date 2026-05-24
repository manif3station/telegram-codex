# telegram-codex

## Description

`telegram-codex` is a Developer Dashboard skill that bridges Telegram Bot API into Codex and keeps two-way Telegram communication attached to one active Codex session through the DD collector runtime.

## What It Solves

Most Telegram bot experiments stop at one-off scripts. They do not stay aligned with:

- Codex startup
- Dashboard runtime management
- repeatable PM/test/release gates
- session-specific conversation state

`telegram-codex` solves that by making Dashboard own the Telegram polling lifecycle.

## Current Runtime Model

After:

```bash
dashboard skills install telegram-codex
```

the managed startup chain is:

- `codex`
- `~/.developer-dashboard/cli/codex`
- `dashboard telegram-codex.start`

When `dashboard telegram-codex.start` runs with `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CODEX_ENABLE_AUTOSTART=1`, it:

1. preserves the saved-session resume logic from `TICKET_REF` and `~/.developer-dashboard/config/codex.json`
2. derives one workspace session id for Telegram collector ownership from the workspace directory name unless `TELEGRAM_CODEX_SESSION_ID` was explicitly set
3. ensures there is exactly one collector named `telegram-codex-<session-id>` in `~/.developer-dashboard/config/config.json`
4. removes duplicate collector entries for that session if they exist and also removes stale same-workspace `telegram-codex-*` collectors that still point at the wrong session id
5. writes the active Codex reply target into `~/.telegram-codex/<session-id>/codex.session`
6. preserves or creates the pairing-security runtime for that session under `~/.telegram-codex/<session-id>/pairing.json`
7. restarts the DD collector with:
   - `cwd` fixed to the workspace where `dashboard telegram-codex.start` was run
   - `command` fixed to `dashboard telegram-codex.check-message <session-id>`
   - `interval` fixed to `5`
   - `rotation.lines` fixed to `100`
   - `mode` fixed to `singleton`
8. recycles any already-running `check-message <session-id>` worker for that session so the new managed behavior replaces stale long-lived code immediately
9. prunes stale orphaned duplicate `codex resume <session-id>` processes for the mapped reply session before polling starts, so long-lived sessions do not keep leaking old live-session workers on the same tty
10. launches the real Codex binary with `--dangerously-bypass-approvals-and-sandbox`

During a managed Telegram reply, `telegram-codex` now also hydrates the reply prompt from recent persisted rows in that same saved Codex session transcript and then journals the inbound Telegram turn plus the outbound reply back into the transcript. That keeps later Telegram follow-up work and later resumed TUI history attached to one shared persisted Codex session instead of leaving Telegram as an isolated side channel.

If the mapped Codex session is already open inside a tmux-backed TUI and the live `codex resume <session-id>` process can be matched back to a tmux pane, the worker now injects the Telegram request into that same live pane instead of immediately falling back to detached `codex exec resume`. In that live mode, the Telegram request becomes a real new TUI turn, the TUI commentary and final answer stream back to Telegram from the same transcript, and later TUI-originated turns can be mirrored back to the paired Telegram chat. Live-pane discovery now prefers the freshest tmux-backed `codex resume <session-id>` process instead of the first stale match, and if the injected turn never shows up in the transcript the worker fails fast and falls back to detached resume with an audit record instead of leaving Telegram stuck on `Codex verbose` plus `Resuming active Codex session`. TUI-originated mirrored turns now also keep Telegram `typing...` active until the final outbound Telegram reply send completes, even when that final assistant turn arrives in a later collector transcript poll.

`dashboard telegram-codex.start --version` is a pure metadata query that proxies the real underlying Codex CLI version output DD expects. DD can probe it safely without creating or restarting collectors.
Successful managed startup now hands off with `exec`, so the wrapper process does not stay resident as an extra long-lived `cli/start` parent after Codex takes over. The managed start path also prepends `--dangerously-bypass-approvals-and-sandbox` before it launches the real Codex process so direct Telegram-owned startup stays non-interactive on the same machine assumptions as managed resumed reply subprocesses. Ambient workspace `OLLAMA_MODEL` is no longer treated as an automatic provider override for Telegram-managed startup. If Telegram-owned startup really needs the Ollama launch profile, set `TELEGRAM_CODEX_OLLAMA_MODEL` explicitly.
If you need runtime diagnostics for a broken managed reply, run:

```bash
dashboard telegram-codex.start --audit
```

That enables a per-session audit trail under `~/.telegram-codex/<session-id>/` without changing the collector contract.
It now also replaces any stale already-running worker for that same session, so the audit-enabled code path actually takes effect immediately instead of waiting for an old long-lived loop to die on its own.

The collector-owned polling loop is now the always-on path. The old standalone listener command is no longer the primary runtime model.
When `codex.session` exists for that collector session, `dashboard telegram-codex.check-message <session-id>` automatically routes replies back through that saved Codex session.
If `codex.session` is missing, the managed reply path falls back to the same saved-session mapping in `~/.developer-dashboard/config/codex.json` that `telegram-codex.start` uses.
Before the polling loop settles in, the worker prunes stale orphaned duplicate `codex resume <session-id>` processes that are older than the freshest live tmux-backed owner on the same tty. That keeps long-running Telegram-managed sessions from accumulating unnecessary resident Codex processes and cuts the avoidable memory footprint of those workspaces.

## What The Skill Supports

Inbound Telegram update metadata:

- text
- photos
- videos
- audio
- voice
- documents and other files

Outbound Telegram actions:

- text replies
- local photo sends
- local audio sends
- local document sends

Telegram-native slash commands:

- `/help`
- `/status`

Attachment handling:

- metadata is available directly in updates and collector processing
- managed `dashboard telegram-codex.check-message <session-id>` now downloads inbound supported media into the session runtime before Codex replies
- downloaded Telegram photos and image documents are attached to resumed Codex replies as real `codex exec resume -i` image inputs
- the Codex prompt still receives `*_local_path=` lines for downloaded files, but non-image media remains a local-path input for tool-based inspection rather than a direct binary model attachment
- direct `dashboard telegram-codex.download <FILE_ID>` and managed inbound-media downloads now use Telegram Bot API `getFile` query-string parameters correctly, so real photo and file downloads work in live runs

## Getting Started

Use this order instead of guessing which command to run first.

1. Change into the project you want Telegram to drive.

```bash
cd ~/projects/my-project
```

2. Register the workspace with Dashboard. This seeds the workspace shell with the `WORKSPACE_REF` / `TICKET_REF` mapping that `telegram-codex.start add` uses later.

```bash
dashboard workspace my-project
```

3. Save the Telegram bot token into the project-local `.env`.

```bash
printf 'TELEGRAM_BOT_TOKEN=123456:telegram-bot-token\n' >> .env
```

4. Make sure `.env` is ignored before you keep working.

```bash
printf '.env\n' >> .gitignore
```

5. Install or refresh the local Codex Telegram bridge.

```bash
dashboard telegram-codex.install 123456:telegram-bot-token
```

6. Start Codex normally inside that project.

```bash
codex
```

7. In Codex, send a small message such as `hi`, then run `/status` and note the active Codex session id.

8. Exit Codex, but stay in the same `dashboard workspace` shell.

9. Bind this workspace to that saved Codex session id from the same workspace shell.

```bash
dashboard telegram-codex.start add <codex-session-id>
```

10. Start or resume the managed Codex + Telegram bridge from that same workspace shell.

```bash
dashboard telegram-codex.start
```

11. If you want the runtime audit trail too, use:

```bash
dashboard telegram-codex.start --audit
```

After that, Telegram can drive the paired Codex session through the collector-owned bridge.

## Direct Command Reference

Use these when you already know the workflow above and need a specific helper.

```bash
dashboard telegram-codex.get-me
dashboard telegram-codex.updates
dashboard telegram-codex.check-message <session-id>
dashboard telegram-codex.download <FILE_ID>
dashboard telegram-codex.reply <CHAT_ID> 'Hello from Codex'
dashboard telegram-codex.pair <HEX_CODE>
dashboard telegram-codex.send-photo <CHAT_ID> ~/Pictures/demo.png
dashboard telegram-codex.send-audio <CHAT_ID> ~/Music/reply.mp3
dashboard telegram-codex.send-document <CHAT_ID> ~/Downloads/report.pdf
dashboard telegram-codex.auto-reply-start
```

## Collector Contract

The collector record created or healed by `dashboard telegram-codex.start` looks like this:

```json
{
  "name": "telegram-codex-<session-id>",
  "interval": 5,
  "rotation": { "lines": 100 },
  "cwd": "<workspace where start was run>",
  "command": "dashboard telegram-codex.check-message <session-id>",
  "mode": "singleton"
}
```

`dashboard telegram-codex.check-message <session-id>` is a long-running polling loop. Dashboard attempts to schedule it every five seconds, but singleton mode plus the same-session pid guard prevents overlap while the existing loop is still alive. When `~/.telegram-codex/<session-id>/codex.session` exists, the worker resumes that Codex session to generate the Telegram reply text. If `listener.offset` is missing or stale but `listener.inbox.jsonl` proves a newer next offset, the worker rewrites `listener.offset` to that recovered value before polling so restart state stays truthful.
While Codex is processing a managed reply, the worker keeps Telegram `typing...` status active through both reply generation and the final outbound Telegram send so the indicator does not disappear before the reply arrives.
Instead of the old placeholder progress heartbeat, the worker now streams real step-by-step Codex verbose events from `codex exec resume --json` into one Telegram trace message that updates in place and stays visible in chat.
Managed Codex-session replies now open that verbose trace by default, including short conversational follow-up messages, and still emit an immediate kickoff line before richer Codex JSON events arrive.
When the mapped session is already live in a tmux-backed Codex TUI, the worker prefers the freshest matching live pane and transcript tailing before it falls back to detached resume. If the live pane never records the injected Telegram turn, the worker fails fast, audits the fallback reason, and retries through detached resume instead of waiting out the full live timeout.
If a Telegram verbose progress update fails mid-run, the worker now records that as a non-fatal progress error and still attempts final delivery. If the resumed Codex subprocess exits early or returns an empty reply, the worker now preserves exit status and stderr-tail detail for diagnosis instead of collapsing to a generic failure.
Before any managed Codex-session reply is allowed, the session now enforces a pairing gate. The first unpaired Telegram message receives one local pairing command reply in the form `d2 telegram-codex.pair <hexcode>`. If the same unpaired user keeps sending messages before that local pair command is run, the worker ignores them. Once the local pair command succeeds, only that paired chat can drive the session; other chats are ignored. The session audit now records explicit pairing decisions such as `pairing.challenge.sent`, `pairing.ignored`, and `pairing.allowed` before managed Codex reply work starts.
For paired chats, supported Telegram slash commands are handled directly by `telegram-codex` before the managed Codex prompt path. Today that direct Telegram command surface is `/help` and `/status`. Surrounding whitespace or newline noise is stripped before command parsing so a padded Telegram `/status` or `/help` message still stays on the direct slash-command path instead of falling through into Codex prompt handling. Unsupported Telegram slash commands are rejected explicitly instead of being forwarded into Codex as ordinary prompt text. When the paired Codex session is already open in a tmux-backed TUI, Telegram `/status` now returns the real rendered Codex status panel from that live pane. If that pane is already showing the status panel, the visible live panel is reused immediately; otherwise `telegram-codex` injects the real Codex `/status` slash command into that pane and captures the rendered panel. If there is no live tmux-backed pane for that session, `telegram-codex` replies explicitly that real Codex `/status` is unavailable instead of returning a synthetic local summary.
The unpaired trigger message itself now stops at that pairing gate. It does not resume Codex, does not inject into a live tmux-backed Codex TUI pane, and does not append into the shared Codex session transcript.
For inbound non-text updates, the worker downloads supported attachments into `~/.telegram-codex/<session-id>/downloads/` before asking Codex to reply. Downloaded Telegram photos and image documents are attached to the resumed Codex session as real image inputs. Other downloaded media still flows by local path for tool-based inspection. Codex can send a non-text reply back by returning directive lines:

```text
telegram_attachment_type=photo|audio|document
telegram_attachment_path=/absolute/local/path
telegram_attachment_caption=optional caption
```

Stop it with Dashboard collector lifecycle commands, for example:

```bash
dashboard stop collector telegram-codex-<session-id>
```

## Session State

The skill keeps per-session Telegram state under:

- `~/.telegram-codex/<session-id>/listener.offset`
- `~/.telegram-codex/<session-id>/listener.inbox.jsonl`
- `~/.telegram-codex/<session-id>/codex.session`
- `~/.telegram-codex/<session-id>/pairing.json`
- `~/.telegram-codex/<session-id>/downloads/`
- `~/.telegram-codex/<session-id>/audit.enabled`
- `~/.telegram-codex/<session-id>/audit.jsonl`
- `~/.telegram-codex/<session-id>/transcript.cursor`

`codex.session` stores the actual Codex session that Telegram replies should resume. That target may be different from the collector session name when `TICKET_REF` maps the workspace to a saved Codex session.
The matching `~/.codex/sessions/...` transcript for that target session is now reused as shared persisted history for managed Telegram replies and receives readable Telegram user and assistant journal rows after each managed exchange.
`pairing.json` stores the paired Telegram chat id or the pending one-time local pairing challenge for that session.
`listener.offset` is healed from `listener.inbox.jsonl` immediately when inbox-ledger recovery proves a newer next offset.
`downloads/` stores inbound media that the managed collector downloaded for Codex inspection before reply generation.
`audit.enabled` opts the collector-owned worker into runtime audit capture.
`audit.jsonl` stores per-event diagnostic rows such as received updates, streamed progress events, progress callback failures, reply delivery failures, and final `codex exec resume` exit details.

## Important Rules

- Do not claim binary media content was read unless the file was downloaded first.
- Do not claim outbound video send support; text, photo, audio, and document sending are implemented.
- Do not claim audio, voice, video, or PDF bytes were attached directly to the model; today only downloaded Telegram photos and image documents are attached as real Codex image inputs.
- Do expect the managed Telegram path to leave a readable verbose progress trace in chat instead of deleting a generic heartbeat message.
- Do expect managed Telegram sessions to stay locked until a local `dashboard telegram-codex.pair <hexcode>` command pairs one Telegram chat to that session.
- Do use `dashboard telegram-codex.start` for the real always-on path.
- Do treat `dashboard telegram-codex.check-message <session-id>` as a managed collector loop, not as a short one-off polling command.
- Do expect managed Telegram task replies to answer directly without boilerplate prefaces and to do the real in-session work before replying instead of sending a promise such as `will be done`.
- Do expect repeated nested `codex` calls inside one managed process tree to skip collector restarts because startup now carries a reentry guard.
