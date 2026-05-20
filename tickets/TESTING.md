# Testing

## Policy

- tests run only inside Docker
- the shared test container definition lives at the workspace root
- this skill keeps its tests in `t/`

## Commands

```bash
docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc 'cd /workspace/skills/telegram-codex && cpanm --quiet --notest --installdeps . && prove -lr t'
docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc 'cd /workspace/skills/telegram-codex && rm -rf cover_db .test-tmp && cpanm --quiet --notest --installdeps . && HARNESS_PERL_SWITCHES=-MDevel::Cover prove -lr t && cover -ignore_covered_err -report text -select lib/Telegram/Codex/Manager.pm -coverage statement -coverage subroutine'
```

## Latest Evidence

- Docker functional gate for `DD-276`:
  - `Files=6, Tests=202`
  - `Result: PASS`
- Docker functional gate for `DD-277`:
  - `Files=6, Tests=212`
  - `Result: PASS`
- Docker functional gate for `DD-278`:
  - `Files=6, Tests=212`
  - `Result: PASS`
- Docker covered gate for `DD-276`:
  - `Files=6, Tests=202`
  - `lib/Telegram/Codex/Manager.pm` statement `100.0`
  - `lib/Telegram/Codex/Manager.pm` subroutine `100.0`
  - `cover -ignore_covered_err` is required only for the intentional child-process stdio redirection statements marked `# uncoverable statement`
- Docker covered gate for `DD-277`:
  - `Files=6, Tests=212`
  - `lib/Telegram/Codex/Manager.pm` statement `100.0`
  - `lib/Telegram/Codex/Manager.pm` subroutine `100.0`
- Docker covered gate for `DD-278`:
  - `Files=6, Tests=212`
  - `lib/Telegram/Codex/Manager.pm` statement `100.0`
  - `lib/Telegram/Codex/Manager.pm` subroutine `100.0`
- Docker functional gate for `DD-279`:
  - `Files=6, Tests=223`
  - `Result: PASS`
- Docker covered gate for `DD-279`:
  - `Files=6, Tests=223`
  - `lib/Telegram/Codex/Manager.pm` statement `100.0`
  - `lib/Telegram/Codex/Manager.pm` subroutine `100.0`
- Docker listener gate:
  - `Files=6, Tests=181`
  - listener state, session-specific runtime paths, inbox ledger, wrapper executability, thin-launcher generation, preserved saved-session resume mapping, no-backlog first auto-start behavior, `.env` discovery paths, and audio/video/voice reply eligibility are covered
- Listener replay-spam regression:
  - Docker now covers the path where `sendMessage` fails and still proves the listener persists the next offset instead of replaying the same inbound Telegram update forever
- Stale-update replay regression:
  - Docker now covers recovery of the next offset from `listener.inbox.jsonl` when `listener.offset` is missing
  - Docker now covers skipping returned updates older than the current next offset so stale Telegram backlog is not appended or auto-replied again
- Passive listener regression:
  - listener no longer sends the placeholder `queued for Codex` reply unless an explicit reply text is passed
- Managed start two-way regression:
  - `dashboard telegram-codex.start` now launches the listener with the concise acknowledgement `Message received. Codex is active here.`
  - transient `getUpdates` transport failures are retried instead of killing the listener immediately
  - stale stored offsets are clamped up to the newer inbox-ledger offset so duplicated older Telegram updates are not replayed
- Earlier covered gate:
  - `lib/Telegram/Codex/Manager.pm` statement `100.0`
  - `lib/Telegram/Codex/Manager.pm` subroutine `100.0`
  - listener runtime partitioning by Codex session id is covered
- Live Telegram proof on 2026-05-20:
  - `./cli/install` created the plugin under `~/.codex/.tmp/plugins/plugins/telegram-codex` and the mirror root when present
  - `./cli/get-me` resolved the configured bot identity successfully
  - `./cli/updates 0 10 0` returned the pending `/start` private DM successfully
  - `./cli/auto-reply-start` replied successfully to that `/start`
  - `./cli/reply <private-chat-id> 'telegram-codex end-to-end check passed'` sent a direct follow-up message successfully
  - `./cli/listen` is now documented as the always-on path, with persistent offset and inbox state under `~/.telegram-codex/<session-id>/`
  - the listener reply rules now cover inbound text, photos, video, audio, voice, and document/file updates
  - a long-running listener session was started from the skill checkout with the listener offset pre-seeded to the latest known Telegram update
  - `PERL5LIB=lib perl -MTelegram::Codex::Manager -e 'Telegram::Codex::Manager->new()->auto_setup()'` wrote a managed `codex` wrapper into `~/.local/bin/codex`
  - a fresh shell resolved `codex` to that managed wrapper instead of the npm global binary
  - direct listener execution with `TELEGRAM_CODEX_LISTENER_PRIME_LATEST=1` was covered in Docker to prove first auto-start primes the latest offset and does not auto-reply to backlog messages
