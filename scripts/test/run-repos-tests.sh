#!/usr/bin/env bash
# Test scripts/repos.sh against the fixture workspace and compare the normalized
# output and exit code of every step with scripts/test/expected/.
#
# Usage: scripts/test/run-repos-tests.sh [--update]
#   --update  rewrite the expected results instead of comparing (review the diff!)
#
# scripts/test/run-repos-tests.ps1 runs the same steps against scripts/repos.ps1 and
# compares with the same expected results, so the two scripts cannot drift apart.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
expected_dir="$here/expected"
update=0
[ "${1:-}" = "--update" ] && update=1

ws_input="$(mktemp -d)"
trap 'rm -rf "$ws_input"' EXIT
"$here/build-fixture.sh" "$ws_input" || exit 1
ws_win="$(cd "$ws_input" && { pwd -W 2>/dev/null || pwd; })"
ws_posix="$(cd "$ws_input" && pwd)"
root="$ws_input/root"
results="$ws_input/results"
mkdir -p "$results"

# sed program: strip carriage returns, normalize separators, replace the temporary
# workspace, mask commit hashes, and mask the script name in hints (each script names
# itself). Lines printed by Git itself are dropped afterwards because their wording
# differs between Git versions; only the messages of the scripts are compared.
sed_program="$(mktemp)"
cat > "$sed_program" <<SED
s/\r\$//
s,\\\\,/,g
s|$ws_win|<ws>|g
s|$ws_posix|<ws>|g
s/\b[0-9a-f]\{7,40\}\b/<sha>/g
s,\(\./\)*scripts/repos\.\(sh\|ps1\),scripts/repos.<ext>,g
SED

run_step() {
    local name="$1"
    shift
    bash "$root/scripts/repos.sh" "$@" > "$results/$name.raw" 2>&1
    local code=$?
    sed -f "$sed_program" "$results/$name.raw" > "$results/$name.sed" || {
        echo "normalization failed for $name" >&2
        exit 1
    }
    grep -v -E '^(Cloning into |done\.$|fatal: |Please make sure|and the repository exists|Already up.to.date|$)'         "$results/$name.sed" > "$results/$name.body" || true
    { cat "$results/$name.body"; echo "exit: $code"; } > "$results/$name.txt"
}

run_step 01-status-before status
run_step 02-clone clone
run_step 03-clone-again clone
echo "local change" > "$root/bravo/local.txt"
run_step 04-status-after-clone status
run_step 05-pull pull

failed=0
for result in "$results"/*.txt; do
    name="$(basename "$result")"
    if [ "$update" -eq 1 ]; then
        cp "$result" "$expected_dir/$name"
        echo "updated $name"
    elif diff -u "$expected_dir/$name" "$result"; then
        echo "ok      $name"
    else
        echo "FAILED  $name" >&2
        failed=1
    fi
done
rm -f "$sed_program"
exit $failed
