# 2026-05-21 Telegram `getFile` Query String Fix

- fixed `telegram_get()` so Telegram Bot API GET parameters are encoded into the request URL query string instead of being mis-sent as HTTP headers
- restored real inbound media download support for both `dashboard telegram-codex.download <FILE_ID>` and the managed collector-owned media reply path
- added Docker-covered regression coverage proving `file_id` and numeric GET parameters are carried in the URL query and not leaked into request headers
