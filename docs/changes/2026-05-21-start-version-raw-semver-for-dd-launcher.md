# 2026-05-21 Start Version Raw Semver For DD Launcher

- changed the top-level `dashboard telegram-codex.start --version` CLI output from JSON to a raw semver line so DD launcher version checks can parse it correctly
- kept the `--version` path side-effect free so repeated DD probe/discovery calls still do not create or restart collectors
