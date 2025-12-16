#!/bin/bash

set -euo pipefail

IFS=$'\n\t'

DRY_RUN=0
MIN_LENGTH=0

usage() {
    echo "Usage: $0 [--dry-run|-n] <input_directory> <output_directory>" >&2
}

# Log a message with a timestamp.
log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

format_cmd() {
    local out=""
    local arg
    for arg in "$@"; do
        out+="$(printf '%q' "$arg") "
    done
    printf '%s' "${out% }"
}

# Execute a command or only log it when DRY_RUN is enabled.
run() {
    if [[ "$DRY_RUN" == "1" ]]; then
        log "DRY_RUN: $(format_cmd "$@")"
        return 0
    fi
    "$@"
}

# Ensure a required command exists in PATH.
require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        log "Missing required command: $1"
        exit 127
    }
}

# Parse options
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
        --)
            shift
            break
            ;;
        -*)
            echo "Error: unknown option: $1" >&2
            usage
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -ne 2 ]]; then
    usage
    exit 1
fi

input_directory="$1"
output_directory="$2"

if [[ "$input_directory" != "/" ]]; then
    input_directory="${input_directory%/}"
fi
if [[ "$output_directory" != "/" ]]; then
    output_directory="${output_directory%/}"
fi

if [[ ! -d "$input_directory" ]]; then
    echo "Error: input directory does not exist: $input_directory" >&2
    exit 1
fi

require_cmd find
require_cmd mktemp
if [[ "$DRY_RUN" != "1" ]]; then
    require_cmd makemkvcon
fi

# Create the output directory if it does not exist
run mkdir -p "$output_directory"

rel_from_input() {
    local path="$1"
    local rel
    rel="${path#"$input_directory"/}"
    if [[ "$rel" == "$path" ]]; then
        printf '%s\n' "."
        return 0
    fi
    printf '%s\n' "$rel"
}

dest_dir_from_rel() {
    local rel_dir="$1"
    if [[ "$rel_dir" == "." ]]; then
        printf '%s\n' "$output_directory"
    else
        printf '%s\n' "$output_directory/$rel_dir"
    fi
}

# Convert a MakeMKV source (ISO file or DVD folder) into the destination directory.
convert_source() {
    local source_label="$1"
    local makemkv_source="$2"
    local dest_dir="$3"
    local base_noext="$4"

    local done_marker
    done_marker="$dest_dir/.iso2mkv.${base_noext}.done"

    if [[ -f "$done_marker" ]] || compgen -G "$dest_dir/${base_noext}"'*.mkv' >/dev/null; then
        log "Skipping (already exists): $source_label"
        return 0
    fi

    run mkdir -p "$dest_dir"

    if [[ "$DRY_RUN" == "1" ]]; then
        log "Would convert: $source_label -> $dest_dir"
        log "Would run: $(format_cmd makemkvcon mkv "$makemkv_source" all "$dest_dir" "--minlength=$MIN_LENGTH")"
        log "Would rename outputs to base: $base_noext"
        return 0
    fi

    local tmp_out
    tmp_out="$(mktemp -d "$dest_dir/.iso2mkv.${base_noext}.XXXXXX")"
    log "Converting: $source_label -> $dest_dir"

    cmd=(makemkvcon mkv "$makemkv_source" all "$tmp_out" "--minlength=$MIN_LENGTH")
    log "Running: $(format_cmd "${cmd[@]}")"
    if ! "${cmd[@]}"; then
        log "Error: makemkvcon failed for: $source_label"
        run rm -rf "$tmp_out"
        return 1
    fi

    declare -a mkv_files=()
    while IFS= read -r -d '' mkv_file; do
        mkv_files+=("$mkv_file")
    done < <(find "$tmp_out" -maxdepth 1 -type f -iname '*.mkv' -print0)

    local mkv_total
    mkv_total=${#mkv_files[@]}
    if [[ $mkv_total -eq 0 ]]; then
        log "Warning: no MKV produced for: $source_label"
        run rm -rf "$tmp_out"
        return 0
    fi

    local -a mkv_files_sorted=()
    IFS=$'\n' mkv_files_sorted=($(printf '%s\n' "${mkv_files[@]}" | LC_ALL=C sort))
    IFS=$'\n\t'

    for i in "${!mkv_files_sorted[@]}"; do
        local idx target
        idx=$((i + 1))
        if [[ $mkv_total -eq 1 ]]; then
            target="$dest_dir/${base_noext}.mkv"
        else
            target="$dest_dir/${base_noext}_$(printf '%02d' "$idx").mkv"
        fi

        if [[ -e "$target" ]]; then
            log "Skipping output (already exists): $target"
            continue
        fi

        run mv "${mkv_files_sorted[$i]}" "$target"
    done

    run rm -rf "$tmp_out"
    run : >"$done_marker"
}

# Find all ISO files and DVD folder structures (VIDEO_TS) and convert them
found_any=0

while IFS= read -r -d '' iso_file; do
    found_any=1
    rel_path="$(rel_from_input "$iso_file")"
    rel_dir="$(dirname "$rel_path")"
    dest_dir="$(dest_dir_from_rel "$rel_dir")"

    iso_base_name="$(basename "$iso_file")"
    iso_base_noext="${iso_base_name%.*}"

    convert_source "$iso_file" "iso:$iso_file" "$dest_dir" "$iso_base_noext"
done < <(find "$input_directory" -type f -iname '*.iso' -print0)

while IFS= read -r -d '' video_ts_dir; do
    found_any=1
    dvd_root="$(dirname "$video_ts_dir")"
    rel_dir_path="$(rel_from_input "$dvd_root")"
    dest_dir="$(dest_dir_from_rel "$rel_dir_path")"

    dvd_base_noext="$(basename "$dvd_root")"

    if [[ "$DRY_RUN" == "1" ]]; then
        convert_source "$dvd_root" "$dvd_root" "$dest_dir" "$dvd_base_noext"
        continue
    fi

    if convert_source "$dvd_root" "$dvd_root" "$dest_dir" "$dvd_base_noext"; then
        continue
    fi
    if convert_source "$dvd_root" "$video_ts_dir" "$dest_dir" "$dvd_base_noext"; then
        continue
    fi
    if convert_source "$dvd_root" "dvd:$dvd_root" "$dest_dir" "$dvd_base_noext"; then
        continue
    fi
    convert_source "$dvd_root" "dvd:$video_ts_dir" "$dest_dir" "$dvd_base_noext"
done < <(find "$input_directory" -type d -iname 'VIDEO_TS' -print0)

if [[ $found_any -eq 0 ]]; then
    echo "No ISO files or VIDEO_TS directories found in $input_directory" >&2
fi
