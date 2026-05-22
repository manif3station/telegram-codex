# telegram-codex Agent Guide

## What This Skill Is For

Use `telegram-codex` when a Codex session needs to communicate through Telegram while keeping Dashboard in control of the polling lifecycle.

This skill gives Codex:

- Telegram update polling
- inbound text, photo, video, audio, voice, and document metadata
- Telegram file download by `file_id`
- outbound text reply
- outbound photo send
- outbound audio send
- outbound document send
- managed two-way Telegram communication through one DD collector per active workspace session

## Runtime Model

The always-on path is no longer a separate ad hoc listener command.

The managed path is:

```bash
dashboard telegram-codex.start
```

That command:

1. keeps the saved-session mapping logic from `TICKET_REF` and `~/.developer-dashboard/config/codex.json`
2. derives a collector session id from:
   - `TELEGRAM_CODEX_SESSION_ID`
   - otherwise the workspace directory name
3. ensures there is exactly one collector named `telegram-codex-<session-id>` in `~/.developer-dashboard/config/config.json`
4. removes duplicates for that collector name and heals stale same-workspace `telegram-codex-*` entries that still point at the wrong session id
5. writes the actual Codex resume target into:

```bash
~/.telegram-codex/<session-id>/codex.session
```

6. restarts:

```bash
dashboard restart collector telegram-codex-<session-id>
```

7. recycles any already-running `check-message <session-id>` worker for that same session so stale long-lived code does not stay active
8. launches the real Codex binary

`dashboard telegram-codex.start --version` is a safe metadata query for DD probe/discovery paths, must not create or restart collectors, and proxies the real underlying Codex CLI version output the DD launcher expects.
Successful managed startup now hands off with `exec`, so the wrapper process should not remain as an extra long-lived `cli/start` parent once Codex is running. Ambient workspace `OLLAMA_MODEL` is intentionally ignored here; use `TELEGRAM_CODEX_OLLAMA_MODEL` only when Telegram-managed startup should explicitly inject the Ollama launch profile.
If the managed reply path is cutting off mid-operation, use:

```bash
dashboard telegram-codex.start --audit
```

That enables per-session audit rows under `~/.telegram-codex/<session-id>/audit.jsonl`.
Because managed startup now recycles the old per-session worker first, `--audit` and newer progress behavior take effect immediately instead of being hidden behind a stale long-lived loop.

When `~/.telegram-codex/<session-id>/codex.session` exists, the collector-owned `dashboard telegram-codex.check-message <session-id>` worker automatically resumes that Codex session to generate the Telegram reply text.
If that file is missing, the managed reply path falls back to the saved-session mapping in `~/.developer-dashboard/config/codex.json`.
When the target session exists, managed replies also hydrate from recent persisted rows in that Codex session transcript and then append readable Telegram user and assistant turns back into the same transcript so later resumed TUI work sees the shared persisted history too.
If the mapped Codex session is already open in a tmux-backed TUI and the live `codex resume <session-id>` process can be matched back to a tmux pane, managed Telegram work is injected into that same live pane instead of always running beside it in detached resume mode. Live-pane selection prefers the freshest matching tmux-backed `codex resume <session-id>` process instead of the first stale match. If the injected Telegram turn never appears in the live transcript, the worker fails fast, audits the reason, and falls back to detached resume. TUI-originated turns are mirrored back to Telegram from the same transcript stream.

## Collector Contract

The collector shape is:

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

`dashboard telegram-codex.check-message <session-id>` is a long-running polling loop. Dashboard may try to start it every five seconds, but singleton mode plus the same-session pid guard prevents overlap while the active loop is still running. When `codex.session` exists for that session, the worker replies through that persisted Codex session automatically. If that file is missing, the worker falls back to the saved-session mapping in `~/.developer-dashboard/config/codex.json`. If `listener.inbox.jsonl` proves a newer next offset than `listener.offset`, the worker rewrites `listener.offset` before polling so restart state stays accurate. While a managed Codex reply is being processed, the worker keeps Telegram `typing...` status active until the final outbound Telegram send attempt completes. Instead of a placeholder heartbeat, the worker now streams real `codex exec resume --json` agent and command events into one Telegram verbose trace message that stays visible in chat. Managed Codex-session replies now open that trace by default, including short conversational follow-up messages, and still emit an immediate kickoff line before richer Codex JSON events arrive. Before that managed reply path is allowed, the session must be paired: the first unpaired Telegram message gets a single local `d2 telegram-codex.pair <hexcode>` reply, later unpaired messages are ignored, and after the local pair command succeeds only that paired chat can drive the session. The session audit records explicit pairing decisions as `pairing.challenge.sent`, `pairing.ignored`, and `pairing.allowed` before managed Codex reply work starts. Supported inbound media is downloaded into the session runtime before Codex replies. Downloaded Telegram photos and image documents are attached to resumed Codex replies as real image inputs; other downloaded media remains local-path-only for tool-based inspection. Codex can return attachment directives to send photos, audio, or documents back to Telegram. When the mapped session is already live in a tmux-backed Codex TUI, the worker prefers the freshest matching live pane and transcript tailing before it falls back to detached resume. If the injected Telegram turn never appears in the live transcript, the worker fails fast, audits the reason, and retries through detached resume instead of leaving the chat stuck on the kickoff line.
The first unpaired trigger message now stops at the pairing gate completely: it does not resume Codex, does not inject into the live TUI, and does not append to the shared Codex transcript.
If a verbose progress edit fails, the worker now records that as a non-fatal progress failure and still attempts the final Telegram reply. If the resumed Codex subprocess exits early or returns an empty reply, the worker now records exit code, signal, stderr tail, and progress events in `audit.jsonl` instead of only surfacing a generic failure.

## What The Skill Can Receive

The skill can receive Telegram update metadata for:

- text
- photos
- video
- audio
- voice
- documents and other files

The polling loop records those inbound updates in:

```bash
~/.telegram-codex/<session-id>/listener.inbox.jsonl
```

Downloaded inbound media for managed replies is stored under:

```bash
~/.telegram-codex/<session-id>/downloads/
```

## What The Skill Can Read Versus Download

This skill reads Telegram update metadata directly.

For actual binary content, download first:

```bash
dashboard telegram-codex.download <FILE_ID>
```

That applies to:

- images
- video
- audio
- voice
- PDFs
- other Telegram-hosted files

The shipped `download` path and the managed collector-owned media reply path both use Telegram Bot API `getFile` query-string parameters correctly, so real Telegram photo and file downloads are expected to work in live runs.

Do not claim a binary attachment was read unless it was downloaded first.
Do not claim audio, voice, video, or PDF bytes were attached directly to the model; only downloaded Telegram photos and image documents are currently attached as real Codex image inputs.

## What The Skill Can Send Back

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

This skill does not currently expose dedicated outbound video sending.

## Key Commands

Install plugin bridge:

```bash
dashboard telegram-codex.install 123456:telegram-bot-token
```

Managed start:

```bash
dashboard telegram-codex.start
```

Collector loop:

```bash
dashboard telegram-codex.check-message <session-id>
```

Inspect updates:

```bash
dashboard telegram-codex.updates
```

Download file:

```bash
dashboard telegram-codex.download <FILE_ID>
```

Managed attachment reply directive:

```text
telegram_attachment_type=photo|audio|document
telegram_attachment_path=/absolute/local/path
telegram_attachment_caption=optional caption
```

## Important Rules For Another Codex Session

- Use `dashboard telegram-codex.start` when Telegram is meant to be the primary communication channel.
- Treat `dashboard telegram-codex.check-message <session-id>` as a collector-owned long-running loop, not as a short one-shot helper.
- Expect one DD collector per workspace session.
- Expect per-session state under `~/.telegram-codex/<session-id>/`.
- Expect true live Telegram/TUI turn sharing only when the mapped Codex session is already open inside tmux and can be matched back to a live `codex resume <session-id>` process.
- Expect nested managed `codex` calls in the same process tree to skip collector restarts because startup carries a reentry guard.
- Expect `~/.telegram-codex/<session-id>/audit.jsonl` to be the first place to inspect when a managed Telegram task starts, streams progress, then cuts off mid-run.
- Do not claim outbound video sending support.
- Do not claim binary attachment content was inspected unless it was downloaded first.
- Do expect the managed Telegram path to keep a readable verbose step trace in chat from real `codex exec resume --json` events instead of a placeholder progress heartbeat.
- Do expect task-style Telegram replies to answer directly without boilerplate prefaces and to do the actual in-session work before sending the final reply.
