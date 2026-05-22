# 2026-05-23 TUI mirror typing guard

- kept Telegram `typing...` active for TUI-originated mirrored Codex turns by starting the managed typing guard on live transcript kickoff
- stopped that mirror typing guard only after the final outbound Telegram reply send path completes
- added multi-poll coverage proving the TUI-originated typing guard stays alive across later collector transcript polls until the final assistant turn arrives
