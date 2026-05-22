## 2026-05-22 live pairing audit hardening

- added explicit `pairing.allowed` audit rows for bypassed, missing-chat, and paired-chat paths
- kept `pairing.challenge.sent` and `pairing.ignored` as the live source of truth for unpaired collector behavior
- extended regression coverage so the first unpaired inbound Telegram message now proves the pairing challenge is written to the session audit as well as sent back to Telegram
