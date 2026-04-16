#!/bin/sh

set -eu

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KARABINER_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
LOG_DIR="$KARABINER_DIR/logs"
STATE_DIR="$KARABINER_DIR/state/repo-sync"
LOG_FILE="$LOG_DIR/repo-sync.log"
LOCAL_ENV_FILE="$SCRIPT_DIR/repo-sync.local.env"
STALE_SECONDS=600
LOCK_FILE=""
LOCK_HELD=0
REPO_LABEL="Repo Sync"
BACKUP_CREATED=0
PUSHED_COMMITS=0

mkdir -p "$LOG_DIR" "$STATE_DIR"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  printf '%s %s\n' "$(timestamp)" "$*" >>"$LOG_FILE"
}

notify() {
  if [ "${AUTO_SYNC_NOTIFY:-1}" = "0" ]; then
    return 0
  fi

  if [ ! -x /usr/bin/osascript ]; then
    return 0
  fi

  /usr/bin/osascript - "$1" "$2" "$3" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  set notificationTitle to item 1 of argv
  set notificationSubtitle to item 2 of argv
  set notificationMessage to item 3 of argv
  display notification notificationMessage with title notificationTitle subtitle notificationSubtitle
end run
APPLESCRIPT
}

notify_repo() {
  notify "Karabiner Repo Sync" "$REPO_LABEL" "$1"
}

fail() {
  log "ERROR: $*"
  notify_repo "Sync failed. Check repo-sync.log"
  printf '%s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [ "$LOCK_HELD" -eq 1 ] && [ -n "$LOCK_FILE" ]; then
    rm -f "$LOCK_FILE"
    log "released lock $LOCK_FILE"
  fi
}

trap cleanup EXIT INT TERM HUP

run_logged() {
  "$@" >>"$LOG_FILE" 2>&1
}

resolve_repo_dir() {
  NOTIFY_OVERRIDE="${AUTO_SYNC_NOTIFY-__unset__}"

  if [ -z "${AUTO_SYNC_REPO_PATH:-}" ] && [ -f "$LOCAL_ENV_FILE" ]; then
    # shellcheck disable=SC1090
    . "$LOCAL_ENV_FILE"
  fi

  if [ "$NOTIFY_OVERRIDE" != "__unset__" ]; then
    AUTO_SYNC_NOTIFY="$NOTIFY_OVERRIDE"
  fi

  AUTO_SYNC_NOTIFY="${AUTO_SYNC_NOTIFY:-1}"

  if [ -z "${AUTO_SYNC_REPO_PATH:-}" ]; then
    fail "Missing config: set AUTO_SYNC_REPO_PATH or create $LOCAL_ENV_FILE"
  fi

  if ! REPO_DIR=$(CDPATH= cd -- "$AUTO_SYNC_REPO_PATH" 2>/dev/null && pwd -P); then
    fail "Configured repo path is not accessible: $AUTO_SYNC_REPO_PATH"
  fi

  REPO_LABEL=$(basename -- "$REPO_DIR")
}

preflight() {
  if [ ! -d "$REPO_DIR" ] || [ ! -r "$REPO_DIR" ]; then
    fail "Configured repo path is not a readable directory: $REPO_DIR"
  fi

  if ! inside_work_tree=$(git -C "$REPO_DIR" rev-parse --is-inside-work-tree 2>>"$LOG_FILE"); then
    fail "Configured path is not inside a git work tree: $REPO_DIR"
  fi

  if [ "$inside_work_tree" != "true" ]; then
    fail "Configured path is not inside a git work tree: $REPO_DIR"
  fi

  if ! BRANCH_NAME=$(git -C "$REPO_DIR" symbolic-ref --quiet --short HEAD 2>>"$LOG_FILE"); then
    fail "Detached HEAD detected for repo: $REPO_DIR"
  fi

  if ! UPSTREAM_REF=$(git -C "$REPO_DIR" rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>>"$LOG_FILE"); then
    fail "No upstream configured for branch $BRANCH_NAME"
  fi
}

compute_lock_file() {
  REPO_HASH=$(printf '%s' "$REPO_DIR" | shasum -a 256 | awk '{print $1}')
  LOCK_FILE="$STATE_DIR/$REPO_HASH.lock"
}

try_lock() {
  if ( set -C; : >"$LOCK_FILE" ) 2>/dev/null; then
    printf '%s\n' "$$" >"$LOCK_FILE"
    LOCK_HELD=1
    log "acquired lock $LOCK_FILE"
    return 0
  fi
  return 1
}

acquire_lock() {
  now_epoch=$(date +%s)

  if try_lock; then
    return 0
  fi

  lock_mtime=$(stat -f %m "$LOCK_FILE" 2>/dev/null || printf '0')
  if [ "$lock_mtime" -gt 0 ]; then
    lock_age=$((now_epoch - lock_mtime))
    if [ "$lock_age" -gt "$STALE_SECONDS" ]; then
      log "stale lock recovery for $LOCK_FILE age=${lock_age}s"
      rm -f "$LOCK_FILE"
      if try_lock; then
        return 0
      fi
    fi
  fi

  log "sync already running"
  notify_repo "Sync already running"
  exit 0
}

create_backup_commit_if_needed() {
  if [ -n "$(git -C "$REPO_DIR" status --porcelain=v1 --untracked-files=all)" ]; then
    log "dirty worktree detected; creating backup commit"
    run_logged git -C "$REPO_DIR" add -A
    if ! git -C "$REPO_DIR" diff --cached --quiet --ignore-submodules --; then
      backup_message="auto backup: $(date +"%Y-%m-%d %H:%M:%S %z")"
      if ! run_logged git -C "$REPO_DIR" commit -m "$backup_message"; then
        fail "Backup commit failed"
      fi
      BACKUP_CREATED=1
      log "created backup commit on $BRANCH_NAME"
    fi
  else
    log "repo clean at trigger start"
  fi
}

fetch_and_rebase() {
  log "fetching upstream for $UPSTREAM_REF"
  if ! run_logged git -C "$REPO_DIR" fetch --prune; then
    fail "Fetch failed"
  fi

  log "rebasing onto $UPSTREAM_REF"
  if ! git -C "$REPO_DIR" rebase "@{u}" >>"$LOG_FILE" 2>&1; then
    git -C "$REPO_DIR" rebase --abort >>"$LOG_FILE" 2>&1 || true
    fail "Rebase failed; aborted rebase and preserved backup commit"
  fi
}

push_if_needed() {
  ahead_count=$(git -C "$REPO_DIR" rev-list --count "@{u}..HEAD" 2>>"$LOG_FILE" || printf '0')
  if [ "$ahead_count" -gt 0 ]; then
    PUSHED_COMMITS=$ahead_count
    log "pushing $ahead_count commit(s) to $UPSTREAM_REF"
    if ! git -C "$REPO_DIR" push >>"$LOG_FILE" 2>&1; then
      fail "Push rejected or failed; manual action required"
    fi
    log "push complete"
  else
    log "nothing to push"
  fi
}

log "sync start"
resolve_repo_dir
preflight
compute_lock_file
acquire_lock
create_backup_commit_if_needed
fetch_and_rebase
push_if_needed
log "sync complete"

if [ "$PUSHED_COMMITS" -gt 0 ]; then
  notify_repo "Sync complete: pushed $PUSHED_COMMITS commit(s)"
elif [ "$BACKUP_CREATED" -eq 1 ]; then
  notify_repo "Sync complete: backup commit created"
else
  notify_repo "Sync complete: no push needed"
fi
