# 2026-05-21 Start Version Proxies Real Codex CLI

- changed `dashboard telegram-codex.start --version` to proxy the real underlying Codex CLI version output instead of the skill version
- kept the `--version` path side-effect free so DD probe/discovery calls still do not create or restart collectors
