#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

STOP_TIMEOUT="${STOP_TIMEOUT:-120}"
RDIFF_VERBOSITY="${RDIFF_VERBOSITY:-5}"
DOCKER_BASE_SRC="${DOCKER_BASE_SRC:-/volumeUSB1/usbshare}"
DOCKER_BASE_DST="${DOCKER_BASE_DST:-/volumeUSB2/usbshare/Docker}"
REQUIRE_MOUNTPOINT="${REQUIRE_MOUNTPOINT:-/volumeUSB2/usbshare}"
LOCK_DIR="${LOCK_DIR:-/tmp/backupDocker.lock.d}"
DRY_RUN="${DRY_RUN:-0}"
PRUNE_OLDER_THAN="${PRUNE_OLDER_THAN:-}"
ONLY_STACKS="${ONLY_STACKS:-}"
SKIP_STACKS="${SKIP_STACKS:-}"
UPDATE_MODE="${UPDATE_MODE:-0}"

# Log a message with a timestamp.
log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

# Print CLI usage information.
usage() {
  cat <<'EOF'
Usage: backupDocker.sh [options]

Options:
  -n, --dry-run                 Print commands instead of executing them
  -h, --help                    Show this help
      --stop-timeout <seconds>  Docker stop timeout (default: 120)
      --rdiff-verbosity <n>     rdiff-backup verbosity level (default: 5)
      --docker-base-src <path>  Base source path for Docker data
      --docker-base-dst <path>  Base destination path for Docker backups
      --lock-dir <path>         Lock directory path
      --require-mountpoint <p>  Require mountpoint to be mounted (default: /volumeUSB2)
      --prune-older-than <time> Prune old increments (e.g. 2W, 90D, 20B)
      --only <csv>              Only backup these stacks (comma-separated)
      --skip <csv>              Skip these stacks (comma-separated)
      --update                  After backup, run compose pull and then compose up -d (requires --only)

Environment fallbacks:
  STOP_TIMEOUT, RDIFF_VERBOSITY, DOCKER_BASE_SRC, DOCKER_BASE_DST, LOCK_DIR, DRY_RUN,
  REQUIRE_MOUNTPOINT, PRUNE_OLDER_THAN, ONLY_STACKS, SKIP_STACKS, UPDATE_MODE
EOF
}

# Parse CLI arguments and set global configuration variables.
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--dry-run)
        DRY_RUN=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --stop-timeout)
        STOP_TIMEOUT="${2:?Missing value for --stop-timeout}"
        shift 2
        ;;
      --rdiff-verbosity)
        RDIFF_VERBOSITY="${2:?Missing value for --rdiff-verbosity}"
        shift 2
        ;;
      --docker-base-src)
        DOCKER_BASE_SRC="${2:?Missing value for --docker-base-src}"
        shift 2
        ;;
      --docker-base-dst)
        DOCKER_BASE_DST="${2:?Missing value for --docker-base-dst}"
        shift 2
        ;;
      --lock-dir)
        LOCK_DIR="${2:?Missing value for --lock-dir}"
        shift 2
        ;;
      --require-mountpoint)
        REQUIRE_MOUNTPOINT="${2:?Missing value for --require-mountpoint}"
        shift 2
        ;;
      --prune-older-than)
        PRUNE_OLDER_THAN="${2:?Missing value for --prune-older-than}"
        shift 2
        ;;
      --only)
        ONLY_STACKS="${2:?Missing value for --only}"
        shift 2
        ;;
      --skip)
        SKIP_STACKS="${2:?Missing value for --skip}"
        shift 2
        ;;
      --update)
        UPDATE_MODE=1
        shift
        ;;
      --)
        shift
        break
        ;;
      *)
        printf '%s\n' "Unknown argument: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done
}

parse_args "$@"

if [[ "$UPDATE_MODE" == "1" ]] && [[ -z "$ONLY_STACKS" ]]; then
  printf '%s\n' "--update can only be used together with --only" >&2
  exit 2
fi

if [[ -z "${SUDO_USER:-}" ]]; then
  printf '%s\n' "This script must be invoked via sudo." >&2
  printf '%s\n' "Example: sudo -E ./backupDocker.sh" >&2
  exit 1
fi

# Ensure a required command exists in PATH.
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "Missing required command: $1"
    exit 127
  }
}

# Check whether a CSV list contains a given item.
csv_contains() {
  local csv="$1"
  local needle="$2"

  [[ -n "$csv" ]] || return 1

  local IFS=','
  local item
  for item in $csv; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# Return success if a mountpoint is currently mounted.
is_mounted() {
  local mountpoint="$1"

  [[ -n "$mountpoint" ]] || return 0
  command -v mount >/dev/null 2>&1 || return 1

  mount | grep -F " on ${mountpoint} " >/dev/null 2>&1 && return 0
  mount | grep -F " on ${mountpoint} (" >/dev/null 2>&1 && return 0
  return 1
}

# Validate destination mount and write permissions and create the destination directory.
prepare_destination() {
  local dst="$1"

  if [[ -n "$REQUIRE_MOUNTPOINT" ]]; then
    if ! is_mounted "$REQUIRE_MOUNTPOINT"; then
      log "Required mountpoint is not mounted: $REQUIRE_MOUNTPOINT"
      exit 1
    fi
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi

  mkdir -p "$dst"
  local testfile
  testfile="$dst/.write_test.$$"
  : >"$testfile" || {
    log "Destination is not writable: $dst"
    exit 1
  }
  rm -f "$testfile" >/dev/null 2>&1 || true
}

# Prune old increments in an rdiff-backup repository based on PRUNE_OLDER_THAN.
prune_increments() {
  local repo="$1"

  [[ -n "$PRUNE_OLDER_THAN" ]] || return 0

  log "Pruning increments older than $PRUNE_OLDER_THAN in: $repo"
  run rdiff-backup --new --force remove increments --older-than "$PRUNE_OLDER_THAN" "$repo"
}

# Execute a command or only log it when DRY_RUN is enabled.
run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY_RUN: $*"
    return 0
  fi
  "$@"
}

# Execute a command and ignore failures (or only log in dry-run mode).
run_allow_fail() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY_RUN: $*"
    return 0
  fi
  "$@" || true
}

declare -a RESTART_COMPOSE_FILES=()

# Cleanup handler: restart services, remove lock, and exit with the original code.
cleanup() {
  trap - EXIT
  local exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    log "Backup failed with exit code $exit_code; attempting to restart services"
  fi

  if command -v docker >/dev/null 2>&1; then
    for f in "${RESTART_COMPOSE_FILES[@]}"; do
      if [[ "$UPDATE_MODE" == "1" ]]; then
        "${COMPOSE_CMD[@]}" -f "$f" up -d >/dev/null 2>&1 || true
      else
        "${COMPOSE_CMD[@]}" -f "$f" start >/dev/null 2>&1 || true
      fi
    done
  fi

  rmdir "$LOCK_DIR" >/dev/null 2>&1 || true
  exit $exit_code
}

trap cleanup EXIT

mkdir "$LOCK_DIR" 2>/dev/null || {
  log "Another backup seems to be running (lock exists at: $LOCK_DIR)"
  exit 1
}

require_cmd docker
require_cmd rdiff-backup

if command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(docker-compose)
else
  COMPOSE_CMD=(docker compose)
fi

EXCLUDES=(
  --exclude '**/.DS_Store'
  --exclude '**/@eaDir'
  --exclude '**/@eaDir/**'
  --exclude '**cache'
  --exclude '**metadata'
)

# Check whether a compose stack has running containers.
compose_has_running_containers() {
  local compose_file="$1"
  local ids

  ids="$("${COMPOSE_CMD[@]}" -f "$compose_file" ps -q 2>/dev/null || true)"
  [[ -n "$ids" ]]
}

# Stop a docker compose stack, back up its directory, then start it again and prune increments.
backup_compose_stack() {
  local compose_file="$1"
  local src="$2"
  local dst="$3"
  shift 3
  local -a extra_excludes=("$@")

  prepare_destination "$dst"

  local was_running=0
  if compose_has_running_containers "$compose_file"; then
    was_running=1
    RESTART_COMPOSE_FILES+=("$compose_file")
    log "Stopping compose stack: $compose_file"
    run_allow_fail "${COMPOSE_CMD[@]}" -f "$compose_file" stop -t "$STOP_TIMEOUT"
  else
    log "Compose stack not running, skipping stop: $compose_file"
  fi

  log "Backing up: $src -> $dst"
  run rdiff-backup --new "-v${RDIFF_VERBOSITY}" backup "${EXCLUDES[@]}" "${extra_excludes[@]}" "$src" "$dst"

  if [[ "$UPDATE_MODE" == "1" ]]; then
    log "Updating compose stack: $compose_file"
    run "${COMPOSE_CMD[@]}" -f "$compose_file" pull
    run "${COMPOSE_CMD[@]}" -f "$compose_file" up -d
  else
    if [[ $was_running -eq 1 ]]; then
      log "Starting compose stack: $compose_file"
      run "${COMPOSE_CMD[@]}" -f "$compose_file" start
    fi
  fi

  prune_increments "$dst"
}

# Back up a path without stopping any services and prune increments.
backup_path() {
  local src="$1"
  local dst="$2"
  shift 2
  local -a extra_excludes=("$@")

  log "Backing up: $src -> $dst"
  prepare_destination "$dst"
  run rdiff-backup --new "-v${RDIFF_VERBOSITY}" backup "${EXCLUDES[@]}" "${extra_excludes[@]}" "$src" "$dst"
  prune_increments "$dst"
}

# Find a compose file within a directory by checking common filenames.
find_compose_file() {
  local dir="$1"
  local -a candidates=(
    "$dir/docker-compose.yml"
    "$dir/docker-compose.yaml"
    "$dir/compose.yml"
    "$dir/compose.yaml"
  )

  local f
  for f in "${candidates[@]}"; do
    if [[ -f "$f" ]]; then
      printf '%s\n' "$f"
      return 0
    fi
  done

  return 1
}

# Iterate over stack directories and back up those with a compose file, honoring only/skip filters.
backup_all_compose_stacks() {
  if [[ ! -d "$DOCKER_BASE_SRC" ]]; then
    log "Source directory does not exist: $DOCKER_BASE_SRC"
    exit 1
  fi

  local d
  for d in "$DOCKER_BASE_SRC"/*; do
    [[ -d "$d" ]] || continue

    local stack_name
    stack_name="$(basename "$d")"

    if [[ -n "$ONLY_STACKS" ]] && ! csv_contains "$ONLY_STACKS" "$stack_name"; then
      continue
    fi
    if [[ -n "$SKIP_STACKS" ]] && csv_contains "$SKIP_STACKS" "$stack_name"; then
      continue
    fi

    local compose_file
    compose_file="$(find_compose_file "$d" 2>/dev/null || true)"
    if [[ -z "$compose_file" ]]; then
      continue
    fi

    local -a extra_excludes=()
    case "$stack_name" in
      shoko)
        extra_excludes=(--exclude '**/Shoko.CLI/images/**' --exclude '**/Shoko.CLI/logs/**')
        ;;
      radarr|sonarr)
        extra_excludes=(--exclude '**MediaCover/')
        ;;
    esac

    backup_compose_stack "$compose_file" "$d" "${DOCKER_BASE_DST}/${stack_name}" "${extra_excludes[@]}"
  done
}

backup_all_compose_stacks

backup_path "/volume1/Pluto/Navidrome" "/volumeUSB2/usbshare/Navidrome"
