# Testing

## Policy

- tests run only inside Docker
- the shared test container definition lives at the workspace root
- this skill keeps its tests in `t/`

## Commands

```bash
docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc 'cd /workspace/skills/telegram-codex && cpanm --quiet --notest --installdeps . && prove -lr t'
docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc 'cd /workspace/skills/telegram-codex && rm -rf cover_db .test-tmp && cpanm --quiet --notest --installdeps . && HARNESS_PERL_SWITCHES=-MDevel::Cover prove -lr t && cover -report text -select lib/Telegram/Codex/Manager.pm'
```

## Latest Evidence

- Docker functional gate:
  - `Files=6, Tests=102`
  - `Result: PASS`
- Docker covered gate:
  - `lib/Telegram/Codex/Manager.pm` statement `100.0`
  - `lib/Telegram/Codex/Manager.pm` subroutine `100.0`
- Live Telegram proof on 2026-05-20:
  - `./cli/install` created the plugin under `~/.codex/.tmp/plugins/plugins/telegram-codex` and the mirror root when present
  - `./cli/get-me` resolved the configured bot identity successfully
  - `./cli/updates 0 10 0` returned the pending `/start` private DM successfully
  - `./cli/auto-reply-start` replied successfully to that `/start`
  - `./cli/reply <private-chat-id> 'telegram-codex end-to-end check passed'` sent a direct follow-up message successfully
