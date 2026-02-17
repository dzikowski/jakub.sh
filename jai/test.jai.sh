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

# Phase 1: start/notify/rm flows
orbit_idx="$("$JAI" start -p "ORBIT" -d "Executing integration tests" --target "$TARGET")"
[[ "$orbit_idx" == "0" ]] || { printf 'FAIL: Expected ORBIT start index 0, got %s\n' "$orbit_idx" >&2; exit 1; }

nova_idx="$("$JAI" start -p "NOVA" -d "Processing deployment pipeline" --target "$TARGET")"
[[ "$nova_idx" == "0" ]] || { printf 'FAIL: Expected NOVA start index 0, got %s\n' "$nova_idx" >&2; exit 1; }

"$JAI" notify -p "ORBIT" -i "$orbit_idx" -d "Result package ready" --target "$TARGET"
"$JAI" notify -p "NOVA" -i "$nova_idx" -d "Handed over for QA review" --target "$TARGET"

status_orbit="$("$JAI" get -p "ORBIT" -i 0 --target "$TARGET")"
status_nova="$("$JAI" get -p "NOVA" --target "$TARGET")"

assert_contains "$status_orbit" "ORBIT#0: REVIEW_REQUIRED - Result package ready" "ORBIT should be in REVIEW_REQUIRED"
assert_contains "$status_nova" "NOVA#0: REVIEW_REQUIRED - Handed over for QA review" "NOVA should be in REVIEW_REQUIRED"

contents="$(<"$TARGET")"
assert_contains "$contents" "# REVIEW_REQUIRED" "REVIEW_REQUIRED header should exist"
assert_contains "$contents" "- **ORBIT#0**: Result package ready" "ORBIT line should include index"
assert_contains "$contents" "- **NOVA#0**: Handed over for QA review" "NOVA line should include index"

# Add another ORBIT index and verify rm -p without index removes all ORBIT entries.
"$JAI" start -p "ORBIT" -d "Secondary execution branch" --target "$TARGET" >/dev/null

orbit_all="$("$JAI" get -p "ORBIT" --target "$TARGET")"
assert_contains "$orbit_all" "ORBIT#0: REVIEW_REQUIRED - Result package ready" "get -p ORBIT should include #0"
assert_contains "$orbit_all" "ORBIT#1: RUNNING - Secondary execution branch" "get -p ORBIT should include #1"

"$JAI" rm -p "ORBIT" -i 1 --target "$TARGET"
after_index_rm="$("$JAI" get -p "ORBIT" --target "$TARGET")"
assert_contains "$after_index_rm" "ORBIT#0: REVIEW_REQUIRED - Result package ready" "rm -p ORBIT -i 1 should keep ORBIT#0"
assert_not_contains "$after_index_rm" "ORBIT#1" "rm -p ORBIT -i 1 should remove ORBIT#1"

"$JAI" rm -p "ORBIT" --target "$TARGET"

final_contents="$(<"$TARGET")"
assert_not_contains "$final_contents" "ORBIT#0" "rm -p ORBIT should remove ORBIT#0"
assert_not_contains "$final_contents" "ORBIT#1" "rm -p ORBIT should remove ORBIT#1"
assert_contains "$final_contents" "NOVA#0" "rm -p ORBIT should not remove NOVA"

printf 'Phase 1 (start/notify/get/rm) passed.\n'

# Phase 2: notify without -i defaults to index 0
rm -f "$TARGET"

"$JAI" start -p "ALPHA" -d "Default index task" --target "$TARGET" >/dev/null
"$JAI" notify -p "ALPHA" -d "Ready for review at default index" --target "$TARGET"
alpha_get="$("$JAI" get -p "ALPHA" --target "$TARGET")"
assert_contains "$alpha_get" "ALPHA#0: REVIEW_REQUIRED - Ready for review at default index" "notify without -i should default to index 0"

printf 'Phase 2 (notify default index 0) passed.\n'

# Phase 3: queue always creates QUEUED entries and auto-assigns index
idx1="$("$JAI" queue -p "ALPHA" -d "First appended task" --target "$TARGET")"
[[ "$idx1" == "1" ]] || { printf 'FAIL: Expected queue index 1, got %s\n' "$idx1" >&2; exit 1; }

idx2="$("$JAI" queue -p "ALPHA" -d "Second appended task" --target "$TARGET")"
[[ "$idx2" == "2" ]] || { printf 'FAIL: Expected queue index 2, got %s\n' "$idx2" >&2; exit 1; }

alpha_all="$("$JAI" get -p "ALPHA" --target "$TARGET")"
assert_contains "$alpha_all" "ALPHA#0: REVIEW_REQUIRED - Ready for review at default index" "ALPHA#0 should exist"
assert_contains "$alpha_all" "ALPHA#1: QUEUED - First appended task" "ALPHA#1 should be QUEUED"
assert_contains "$alpha_all" "ALPHA#2: QUEUED - Second appended task" "ALPHA#2 should be QUEUED"

# queue on a fresh project starts at 0
idx_fresh="$("$JAI" queue -p "BETA" -d "Brand new project" --target "$TARGET")"
[[ "$idx_fresh" == "0" ]] || { printf 'FAIL: Expected queue index 0 for fresh project, got %s\n' "$idx_fresh" >&2; exit 1; }

beta_get="$("$JAI" get -p "BETA" --target "$TARGET")"
assert_contains "$beta_get" "BETA#0: QUEUED - Brand new project" "BETA#0 should be QUEUED"

printf 'Phase 3 (queue) passed.\n'

# Phase 4: start creates RUNNING entries and auto-assigns index
rm -f "$TARGET"

sidx0="$("$JAI" start -p "GAMMA" -d "First running task" --target "$TARGET")"
[[ "$sidx0" == "0" ]] || { printf 'FAIL: Expected start index 0, got %s\n' "$sidx0" >&2; exit 1; }

sidx1="$("$JAI" start -p "GAMMA" -d "Second running task" --target "$TARGET")"
[[ "$sidx1" == "1" ]] || { printf 'FAIL: Expected start index 1, got %s\n' "$sidx1" >&2; exit 1; }

gamma_all="$("$JAI" get -p "GAMMA" --target "$TARGET")"
assert_contains "$gamma_all" "GAMMA#0: RUNNING - First running task" "GAMMA#0 should be RUNNING"
assert_contains "$gamma_all" "GAMMA#1: RUNNING - Second running task" "GAMMA#1 should be RUNNING"

# start and queue share the same index sequence
aidx="$("$JAI" queue -p "GAMMA" -d "Queued after starts" --target "$TARGET")"
[[ "$aidx" == "2" ]] || { printf 'FAIL: Expected queue index 2 after two starts, got %s\n' "$aidx" >&2; exit 1; }

gamma_full="$("$JAI" get -p "GAMMA" --target "$TARGET")"
assert_contains "$gamma_full" "GAMMA#2: QUEUED - Queued after starts" "GAMMA#2 should be QUEUED"

# Typical workflow: start, then notify
"$JAI" notify -p "GAMMA" -i "$sidx0" -d "Done, ready for review" --target "$TARGET"
gamma_review="$("$JAI" get -p "GAMMA" -i 0 --target "$TARGET")"
assert_contains "$gamma_review" "GAMMA#0: REVIEW_REQUIRED - Done, ready for review" "GAMMA#0 should be REVIEW_REQUIRED after notify"

printf 'Phase 4 (start) passed.\n'

printf '\nAll verifications passed.\n\n'
printf 'Final target file contents:\n'
cat "$TARGET"
