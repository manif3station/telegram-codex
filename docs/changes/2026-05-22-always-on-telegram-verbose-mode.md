# Always-On Telegram Verbose Mode

## Summary

Managed Telegram Codex-session replies now open the verbose trace for every reply, not only messages that match a task-style classifier.

## Details

- removed the remaining managed verbose gate tied to task-phrase classification
- conversational follow-up messages such as `These make it better` now show progress before the final reply
- the `Resuming active Codex session` kickoff line still appears before richer streamed Codex JSON events arrive

## Verification

- Docker functional gate passed at `Files=6, Tests=488`
- Docker covered gate passed at `Files=6, Tests=488`
- `lib/Telegram/Codex/Manager.pm` statement coverage `100.0`
- `lib/Telegram/Codex/Manager.pm` subroutine coverage `100.0`
