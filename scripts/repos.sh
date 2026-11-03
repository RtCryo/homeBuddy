#!/usr/bin/env bash
# Manage the homeBuddy service repositories listed in repos.txt.
#
# Usage: scripts/repos.sh [clone|pull|status]
#   clone   clone every missing repository (default)
#   pull    fast-forward every repository whose working tree is clean
#   status  show branch, local changes, and ahead/behind counts
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$root/repos.txt"
command="${1:-clone}"
failures=0

read_manifest() {
    grep -v -E '^\s*(#|$)' "$manifest"
}

clone_repo() {
    local name="$1" url="$2" branch="$3" dir="$root/$1"
    if [ -d "$dir/.git" ]; then
        echo "= $name: already present"
        return
    fi
    if [ -e "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
        echo "! $name: $dir exists but is not a Git repository; skipped" >&2
        failures=$((failures + 1))
        return
    fi
    echo "+ $name: cloning $url ($branch)"
    if ! git clone --branch "$branch" "$url" "$dir"; then
        echo "! $name: clone failed (does the remote exist and do you have access?)" >&2
        failures=$((failures + 1))
    fi
}

pull_repo() {
    local name="$1" dir="$root/$1"
    if [ ! -d "$dir/.git" ]; then
        echo "! $name: missing, run 'scripts/repos.sh clone'" >&2
        failures=$((failures + 1))
        return
    fi
    if [ -n "$(git -C "$dir" status --porcelain)" ]; then
        echo "~ $name: local changes, skipped"
        return
    fi
    if ! git -C "$dir" remote get-url origin >/dev/null 2>&1; then
        echo "~ $name: no origin remote, skipped"
        return
    fi
    echo "> $name: pulling"
    if ! git -C "$dir" pull --ff-only; then
        echo "! $name: pull failed" >&2
        failures=$((failures + 1))
    fi
}

status_repo() {
    local name="$1" dir="$root/$1"
    if [ ! -d "$dir/.git" ]; then
        printf '%-15s missing\n' "$name"
        return
    fi
    local branch changes tracking="no upstream"
    branch="$(git -C "$dir" branch --show-current)"
    changes="$(git -C "$dir" status --porcelain | wc -l | tr -d ' ')"
    if git -C "$dir" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
        read -r ahead behind < <(git -C "$dir" rev-list --left-right --count 'HEAD...@{upstream}')
        tracking="ahead $ahead, behind $behind"
    fi
    printf '%-15s %-20s %3s changed  %s\n' "$name" "${branch:-detached}" "$changes" "$tracking"
}

case "$command" in
    clone | pull | status) ;;
    *)
        echo "Usage: $0 [clone|pull|status]" >&2
        exit 2
        ;;
esac

while read -r name url branch; do
    case "$command" in
        clone) clone_repo "$name" "$url" "$branch" ;;
        pull) pull_repo "$name" ;;
        status) status_repo "$name" ;;
    esac
done < <(read_manifest)

exit $((failures > 0))
