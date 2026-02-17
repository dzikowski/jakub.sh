#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAI="$SCRIPT_DIR/jai.sh"
TARGET="$SCRIPT_DIR/.verify-status.md"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'FAIL: %s\nExpected to find: %s\n' "$msg" "$needle" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'FAIL: %s\nUnexpectedly found: %s\n' "$msg" "$needle" >&2
    exit 1
  fi
}

cleanup() {
  rm -f "$TARGET"
}
trap cleanup EXIT

printf 'Running jai verification...\n'
rm -f "$TARGET"

# Two invented projects move through QUEUED -> RUNNING -> REVIEW_REQUIRED.
"$JAI" set -p "ORBIT" -i 1 -s QUEUED -d "Awaiting scheduler slot" --target "$TARGET"
"$JAI" set -p "NOVA" -i 2 -s QUEUED -d "Waiting for dependency update" --target "$TARGET"

"$JAI" set -p "ORBIT" -i 1 -s RUNNING -d "Executing integration tests" --target "$TARGET"
"$JAI" set -p "NOVA" -i 2 -s RUNNING -d "Processing deployment pipeline" --target "$TARGET"

"$JAI" set -p "ORBIT" -i 1 -s REVIEW_REQUIRED -d "Result package ready" --target "$TARGET"
"$JAI" set -p "NOVA" -i 2 -s REVIEW_REQUIRED -d "Handed over for QA review" --target "$TARGET"

status_orbit="$("$JAI" get -p "ORBIT" -i 1 --target "$TARGET")"
status_nova="$("$JAI" get -p "NOVA" --target "$TARGET")"

assert_contains "$status_orbit" "ORBIT#1: REVIEW_REQUIRED - Result package ready" "ORBIT should be in REVIEW_REQUIRED"
assert_contains "$status_nova" "NOVA#2: REVIEW_REQUIRED - Handed over for QA review" "NOVA should be in REVIEW_REQUIRED"

contents="$(<"$TARGET")"
assert_contains "$contents" "# REVIEW_REQUIRED" "REVIEW_REQUIRED header should exist"
assert_contains "$contents" "- **ORBIT#1**: Result package ready" "ORBIT line should include index"
assert_contains "$contents" "- **NOVA#2**: Handed over for QA review" "NOVA line should include index"

# Add another ORBIT index and verify rm -p without index removes all ORBIT entries.
"$JAI" set -p "ORBIT" -i 3 -s RUNNING -d "Secondary execution branch" --target "$TARGET"

orbit_all="$("$JAI" get -p "ORBIT" --target "$TARGET")"
assert_contains "$orbit_all" "ORBIT#1: REVIEW_REQUIRED - Result package ready" "get -p ORBIT should include #1"
assert_contains "$orbit_all" "ORBIT#3: RUNNING - Secondary execution branch" "get -p ORBIT should include #3"

"$JAI" rm -p "ORBIT" -i 3 --target "$TARGET"
after_index_rm="$("$JAI" get -p "ORBIT" --target "$TARGET")"
assert_contains "$after_index_rm" "ORBIT#1: REVIEW_REQUIRED - Result package ready" "rm -p ORBIT -i 3 should keep ORBIT#1"
assert_not_contains "$after_index_rm" "ORBIT#3" "rm -p ORBIT -i 3 should remove ORBIT#3"

"$JAI" rm -p "ORBIT" --target "$TARGET"

final_contents="$(<"$TARGET")"
assert_not_contains "$final_contents" "ORBIT#1" "rm -p ORBIT should remove ORBIT#1"
assert_not_contains "$final_contents" "ORBIT#3" "rm -p ORBIT should remove ORBIT#3"
assert_contains "$final_contents" "NOVA#2" "rm -p ORBIT should not remove NOVA"

printf 'Verification passed.\n\n'
printf 'Final target file contents:\n'
printf '%s\n' "$final_contents"
