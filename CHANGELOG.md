# Changelog

All notable changes to MinMacs. Format follows [Keep a Changelog](https://keepachangelog.com/).

## [1.0.0] - 2026-09-29

### Added
- Menu bar plan: apps grouped into Will close, Unsorted, Kept, plus system background load, each with CPU and memory. Helpers attributed to their owning app the way Activity Monitor does.
- MinMacs Now: graceful quit of the close list with a confirmation listing exactly what goes. Restore relaunches them in the background.
- Per-app submenu to move between Close, Keep and Unsorted, or quit one app. Rules stored in `~/Library/Application Support/MinMacs/rules.json` with sensible defaults.
- CLI: `minmacs plan [--json]`, `run [--yes] [--only <bundle-id>]`, `restore`, `rules`.
- URL scheme: `minmacs://run|run-now|restore|login-on|login-off|quit`.
- Also Turn On Insomnia option. Launch at Login. Universal binary. `install.sh`, `uninstall.sh`.
