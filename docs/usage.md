# Usage

## Install The Skill

```bash
dashboard skills install telegram-codex
```

## Recommended Workflow

Use this path when you want Telegram to drive a real project session instead of starting from raw helper commands.

1. Change into the project you want Telegram to control.

```bash
cd ~/projects/my-project
```

2. Open the Dashboard workspace. This seeds `WORKSPACE_REF` and `TICKET_REF`, which `telegram-codex.start add` uses when it stores the Codex session mapping.

```bash
dashboard workspace my-project
```

3. Save the bot token into the project-local `.env`.

```bash
printf 'TELEGRAM_BOT_TOKEN=123456:telegram-bot-token\n' >> .env
```

4. Ignore `.env` before you keep working.

```bash
printf '.env\n' >> .gitignore
```

5. Install or refresh the local Codex Telegram plugin bridge.

```bash
dashboard telegram-codex.install 123456:telegram-bot-token
```

6. Start Codex in that same workspace shell.

```bash
codex
```

7. Send a small prompt such as `hi`, then run `/status` and note the active Codex session id.

8. Exit Codex, but stay in the same `dashboard workspace` shell.

9. Save the Codex session mapping for this workspace.

```bash
dashboard telegram-codex.start add <codex-session-id>
```

10. Start or resume the managed Telegram bridge.

```bash
dashboard telegram-codex.start
```

11. If you want the per-session audit trail too, use:

```bash
dashboard telegram-codex.start --audit
```

## Install The Local Codex Telegram Plugin

```bash
dashboard telegram-codex.install 123456:telegram-bot-token
```

That command writes the local Codex plugin, the stdio MCP config, the plugin-local `.env`, and the marketplace entry used by Codex.

## Start The Managed Telegram Runtime

Use:

```bash
dashboard telegram-codex.start
```

or launch Codex normally through the managed wrapper:

```bash
codex
```

With `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CODEX_ENABLE_AUTOSTART=1`, `telegram-codex.start` now does this:

1. loads the saved Codex-session mapping from `~/.developer-dashboard/config/codex.json` when `TICKET_REF` points to one
2. derives a stable Telegram collector session id from:
   - `TELEGRAM_CODEX_SESSION_ID`
   - otherwise the workspace directory name
3. ensures there is exactly one `telegram-codex-<session-id>` collector in `~/.developer-dashboard/config/config.json`
4. removes duplicates for that same collector name and heals stale same-workspace `telegram-codex-*` entries that still point at the wrong session id
5. writes the active Codex resume target to `~/.telegram-codex/<session-id>/codex.session`
6. preserves or creates pairing-security runtime in `~/.telegram-codex/<session-id>/pairing.json`
7. runs:

```bash
dashboard restart collector telegram-codex-<session-id>
```

8. recycles any already-running `dashboard telegram-codex.check-message <session-id>` worker for that same session
9. launches the real Codex binary

`dashboard telegram-codex.start --version` is intentionally side-effect free and proxies the real Codex CLI version output DD launcher checks expect, so DD command-family discovery can probe it without touching collectors.
On a real startup, the launcher now uses `exec` for real Codex handoff, so a successful run does not leave an extra resident `cli/start` wrapper process behind.
Ambient workspace `OLLAMA_MODEL` is ignored by Telegram-managed startup. If you intentionally want Telegram-managed startup to inject the Ollama launch profile, set `TELEGRAM_CODEX_OLLAMA_MODEL` explicitly.
If you need managed-reply runtime diagnostics, start with:

```bash
dashboard telegram-codex.start --audit
```

That enables per-session audit rows in `~/.telegram-codex/<session-id>/audit.jsonl`.
Because startup now recycles an already-running worker for that session before the collector restart, the audited code path takes effect immediately instead of leaving an old long-lived worker alive.

If `codex.session` is missing later, the managed reply path falls back to the same saved-session mapping in `~/.developer-dashboard/config/codex.json` instead of blindly using the collector session id.
When the saved Codex session exists, managed Telegram replies now also hydrate from recent persisted transcript rows for that same Codex session and then append readable Telegram user and assistant turns back into it. That keeps Telegram follow-up work and later resumed TUI history attached to one shared persisted Codex session.
If that mapped Codex session is already open in a tmux-backed TUI and the live `codex resume <session-id>` process can be matched back to a tmux pane, the worker now injects the Telegram request into that same live pane. In that live mode, the open TUI sees the Telegram-originated turn directly, and the paired Telegram chat receives progress plus the final answer from the same live session transcript. If no matching tmux pane is found, the runtime falls back to detached `codex exec resume`.

## Collector-Owned Polling Loop

The collector command is:

```bash
dashboard telegram-codex.check-message <session-id>
```

This is a long-running polling loop, not a short one-shot helper.

The collector definition installed or healed by `telegram-codex.start` is:

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

Dashboard may try to schedule it every five seconds, but singleton mode plus the same-session pid guard prevents a second `check-message <session-id>` copy from starting while the existing loop is still running. If `~/.telegram-codex/<session-id>/codex.session` exists, the worker automatically resumes that Codex session to generate the Telegram reply. If that file is missing, the worker falls back to the saved-session mapping in `~/.developer-dashboard/config/codex.json`. If `listener.inbox.jsonl` proves a newer next offset than `listener.offset`, the worker rewrites `listener.offset` before polling so restart state and replay diagnostics stay aligned. While that managed reply is being processed, the worker keeps Telegram `typing...` status active until the final outbound Telegram send attempt completes. Instead of the old placeholder `Codex is still working on your request...` heartbeat, the worker now streams real `codex exec resume --json` step events into one Telegram trace message that updates in place and remains visible after delivery. Managed Codex-session replies now open that verbose trace by default, including short conversational follow-up messages, and still emit an immediate kickoff line before richer Codex JSON events arrive. When the mapped session is already live in a tmux-backed Codex TUI, the worker now prefers live pane injection and transcript tailing before it falls back to detached resume. TUI-originated turns are also mirrored back into the paired Telegram chat from the same transcript stream.
Before any managed Codex-session reply is allowed, the session pairing gate must be satisfied. The first unpaired Telegram message receives a single pairing reply in the form `d2 telegram-codex.pair <hexcode>`. If that user keeps sending messages before the local pair command is run, the worker ignores them. Once the local pair command succeeds, only that paired Telegram chat can drive the session. The per-session audit records explicit pairing decisions as `pairing.challenge.sent`, `pairing.ignored`, and `pairing.allowed` before managed Codex reply work starts.
If a verbose progress edit fails, that failure is now treated as non-fatal and the worker still attempts final Telegram delivery. If the resumed Codex subprocess exits early or returns no final text, the worker now records exit code, signal, stderr tail, and streamed progress events in the audit file so the cut-off can be diagnosed.
Before that managed reply is generated, supported inbound Telegram media is downloaded into the session runtime. Downloaded Telegram photos and image documents are attached to resumed Codex replies as real `codex exec resume -i` image inputs. Other downloaded media is still exposed through `*_local_path=` lines in the reply prompt for tool-based inspection.
Managed task replies also tell Codex to answer directly without boilerplate prefaces and to do the actual work before replying instead of returning promise-only placeholders such as `will be done`.
Nested managed `codex` invocations inside the same process tree inherit a startup reentry guard, so they do not keep re-running collector restart side effects.

Stop it with Dashboard:

```bash
dashboard stop collector telegram-codex-<session-id>
```

## Pair A Session To The Pending Telegram Chat

When a session is unpaired, the first inbound Telegram message gets this reply:

```bash
d2 telegram-codex.pair <HEX_CODE>
```

Run that locally in the same workspace:

```bash
dashboard telegram-codex.pair <HEX_CODE>
```

That binds the pending Telegram chat to the current workspace session. After that, the paired chat works normally and other chats are ignored.

## Poll Updates Directly

```bash
dashboard telegram-codex.updates
```

That update payload can include metadata for:

- text
- photos
- video
- audio
- voice
- documents/files

## Download Inbound Media

```bash
dashboard telegram-codex.download <FILE_ID>
```

Use that for photos, videos, audio, voice, PDFs, and other Telegram-hosted files whenever the actual content must be inspected.

The managed `check-message` loop now performs that download step automatically for inbound supported media before Codex replies.
The direct `download` command and the managed collector-owned media path both use Telegram Bot API `getFile` query-string parameters correctly, so real inbound Telegram photo and file downloads work in live runs.

## Send Replies

Text:

```bash
dashboard telegram-codex.reply <CHAT_ID> 'Message received'
```

Photo:

```bash
dashboard telegram-codex.send-photo <CHAT_ID> ~/Pictures/demo.png
```

Audio:

```bash
dashboard telegram-codex.send-audio <CHAT_ID> ~/Music/reply.mp3
```

Document:

```bash
dashboard telegram-codex.send-document <CHAT_ID> ~/Downloads/report.pdf
```

Managed Codex replies can also send those files back automatically by returning:

```text
telegram_attachment_type=photo|audio|document
telegram_attachment_path=/absolute/local/path
telegram_attachment_caption=optional caption
```

## `/start` Acknowledgement Helper

```bash
dashboard telegram-codex.auto-reply-start
```

## Session Runtime Files

Per-session runtime state lives under:

- `~/.telegram-codex/<session-id>/listener.offset`
- `~/.telegram-codex/<session-id>/listener.inbox.jsonl`
- `~/.telegram-codex/<session-id>/codex.session`
- `~/.telegram-codex/<session-id>/pairing.json`
- `~/.telegram-codex/<session-id>/downloads/`
- `~/.telegram-codex/<session-id>/audit.enabled`
- `~/.telegram-codex/<session-id>/audit.jsonl`
- `~/.telegram-codex/<session-id>/transcript.cursor`

`listener.offset` keeps the next Telegram update offset and is healed immediately from the inbox ledger when inbox recovery proves a newer next offset.

`listener.inbox.jsonl` keeps the per-session inbound update ledger.

`transcript.cursor` tracks how far the worker has already mirrored the shared Codex transcript back into Telegram for TUI-originated live turns.

`codex.session` keeps the real Codex session that the collector-owned `check-message <session-id>` worker resumes to generate Telegram replies.
The matching `~/.codex/sessions/...` transcript for that target session is now reused as the shared persisted history source for managed Telegram replies and receives readable Telegram user and assistant journal rows after each managed exchange.
`pairing.json` keeps the paired chat id or the pending pairing challenge for that session.
`downloads/` keeps inbound supported Telegram media that was downloaded for Codex before reply generation.
`audit.enabled` turns on runtime audit capture for that collector session.
`audit.jsonl` records received updates, progress-stream failures, `codex exec resume` progress events, stderr-tail details, and final reply success or failure.

## Media Handling Rule

`telegram-codex` can receive and route metadata for text, images, video, audio, voice, PDFs, and other files.

Downloaded Telegram photos and image documents are the only inbound media currently attached directly to the resumed Codex model call as binary image inputs.
Downloaded audio, voice, video, PDFs, and other non-image files remain local-path inputs for tool-based inspection in the resumed Codex session.

It must not claim that a binary attachment was read just because the update metadata arrived. Download the file by `file_id` first when the content itself matters.
