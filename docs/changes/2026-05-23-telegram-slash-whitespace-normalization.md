# 2026-05-23 Telegram slash whitespace normalization

- normalized Telegram slash-command parsing so supported commands such as `/status` and `/help` still match when the Telegram text has surrounding whitespace or newline noise
- kept ordinary non-slash Telegram text out of the direct slash-command path while closing the real prompt-fallthrough bug for whitespace-padded slash commands
