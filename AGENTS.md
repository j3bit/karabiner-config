# Repository Guidelines

## Project Structure & Module Organization
`karabiner.json` is the top-level Karabiner-Elements configuration and currently binds `f18` to the sleep script and `f19` to the sync script. Shell automation lives in `scripts/`: `system-sleep.sh` handles the sleep action, `repo-sync.sh` contains the sync workflow, and `repo-sync.example.env` is the template for private local settings. `README.md` is the primary user-facing setup document. Local runtime output belongs in `logs/`, `state/`, `automatic_backups/`, and `.omx/`; these paths are ignored and should not be committed.

## Build, Test, and Development Commands
- `cp scripts/repo-sync.example.env scripts/repo-sync.local.env` creates a local config stub.
- `sh -n scripts/system-sleep.sh scripts/repo-sync.sh` checks shell syntax before committing script changes.
- `sh scripts/repo-sync.sh` runs the sync flow manually outside Karabiner for local verification.
- `python3 -m json.tool karabiner.json >/dev/null` validates JSON formatting and syntax.
- `git status --short` confirms that only intended tracked files changed.

## Coding Style & Naming Conventions
Use POSIX `sh`; keep the shebang as `#!/bin/sh` and avoid Bash-only features. Indent shell blocks with two spaces inside functions and conditionals, and prefer small, single-purpose functions such as `preflight` or `push_if_needed`. Keep environment variables uppercase (`AUTO_SYNC_REPO_PATH`), functions lowercase with underscores, and log/state paths explicit. In `karabiner.json`, preserve four-space indentation and descriptive rule text such as `F18 -> system sleep` and `F19 -> repo auto-backup sync`.

## Testing Guidelines
There is no formal test suite yet, so changes should ship with targeted manual validation. At minimum, run `sh -n scripts/system-sleep.sh scripts/repo-sync.sh`, validate `karabiner.json`, and exercise the sync script against a disposable or non-critical git repository. When changing notifications, locking, rebase behavior, or sleep behavior, include the exact command used and the observed result in the PR notes.

## Commit & Pull Request Guidelines
Recent history uses short, imperative commit subjects, for example: `Publish a shareable Karabiner F16 git-sync setup`. Keep subjects concise and outcome-focused. PRs should explain the user-visible change, list any config or hotkey updates, and note manual verification steps. Include screenshots only when modifying Karabiner UI-facing assets or setup documentation.

## Security & Configuration Tips
Never commit `scripts/repo-sync.local.env`; it contains machine-specific paths. Treat `logs/` as potentially sensitive because command output may include repository names or git errors. If you change the script path or trigger key, update both `karabiner.json` and `README.md` in the same patch.
