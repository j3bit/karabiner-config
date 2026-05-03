# karabiner-config

Minimal Karabiner-Elements config for two hotkeys:

- `F18` turns the display off when tapped, and runs `scripts/system-sleep.sh` to put macOS to sleep when held for 500 ms
- `F24` runs `scripts/repo-sync.sh`
- the repo sync script auto-backs up a target git repo by:
  - validating the repo and upstream
  - creating a backup commit when the worktree is dirty
  - fetching and rebasing onto upstream
  - pushing on success
  - stopping safely on conflict or push failure

## Files

- `karabiner.json` — Karabiner profile with the `F18` and `F24` rules
- `scripts/system-sleep.sh` — sleep trigger logic
- `scripts/repo-sync.sh` — sync logic
- `scripts/repo-sync.example.env` — setup template
- `.gitignore` — excludes local config, logs, runtime state, backups, and OMX state

## Install

This repository assumes the scripts live at:

```sh
$HOME/.config/karabiner/scripts/system-sleep.sh
$HOME/.config/karabiner/scripts/repo-sync.sh
```

Choose one:

1. clone or symlink this repo to `~/.config/karabiner`, or
2. keep it elsewhere and update the `shell_command` path in `karabiner.json`

`karabiner.json` in this repo is a **full top-level config file**, not just a rule snippet. Either:

- replace your existing config intentionally, or
- merge the `F18 tap -> display sleep, hold -> system sleep` and `F24 -> repo auto-backup sync` rules into your existing Karabiner profile manually

## Local setup

1. Copy the example config:

   ```sh
   cp scripts/repo-sync.example.env scripts/repo-sync.local.env
   ```

2. Edit `scripts/repo-sync.local.env`:

   ```sh
   AUTO_SYNC_REPO_PATH="$HOME/path/to/obsidian-vault-repo"
   AUTO_SYNC_NOTIFY=1
   ```

3. Keep `scripts/repo-sync.local.env` private. It is gitignored by default.

## Notifications

- `AUTO_SYNC_NOTIFY=1` enables macOS notifications
- `AUTO_SYNC_NOTIFY=0` suppresses them

## Logs and state

- sleep log: `logs/system-sleep.log`
- log file: `logs/repo-sync.log`
- lock/state files: `state/repo-sync/`
