#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAI="$SCRIPT_DIR/jai.sh"
JAI_HOOKS="$SCRIPT_DIR/jai-cursorhooks.sh"
TARGET="$SCRIPT_DIR/.verify-status.md"
INSTALL_DIR="$SCRIPT_DIR/.verify-cursor-install"
INSTALL_DIR_DEBUG="$SCRIPT_DIR/.verify-cursor-install-debug"

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

assert_file_contains() {
  local path="$1"
  local needle="$2"
  local msg="$3"
  local file_contents=""
  file_contents="$(<"$path")"
  assert_contains "$file_contents" "$needle" "$msg"
}

cleanup() {
  rm -f "$TARGET"
  rm -rf "$INSTALL_DIR" "$INSTALL_DIR_DEBUG"
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

# Phase 2b: notify without -d reuses current description
"$JAI" start -p "COPYDESC" -d "Keep this description" --target "$TARGET" >/dev/null
"$JAI" notify -p "COPYDESC" --target "$TARGET"
copydesc_get="$("$JAI" get -p "COPYDESC" -i 0 --target "$TARGET")"
assert_contains "$copydesc_get" "COPYDESC#0: REVIEW_REQUIRED - Keep this description" "notify without -d should reuse existing description"

printf 'Phase 2b (notify description reuse) passed.\n'

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

# Phase 5: install-cursorhooks + hook command flow via jai-cursorhooks
rm -rf "$INSTALL_DIR" "$INSTALL_DIR_DEBUG"
PATH="$SCRIPT_DIR:$PATH" "$JAI" install-cursorhooks "$INSTALL_DIR" >/dev/null
[[ -f "$INSTALL_DIR/.cursor/hooks.json" ]] || { printf 'FAIL: hooks.json was not created\n' >&2; exit 1; }

installed_hooks_json="$(<"$INSTALL_DIR/.cursor/hooks.json")"
assert_contains "$installed_hooks_json" "\"version\": 1" "install-cursorhooks should write hooks schema version"
assert_contains "$installed_hooks_json" "\"beforeSubmitPrompt\"" "install-cursorhooks should configure beforeSubmitPrompt"
assert_contains "$installed_hooks_json" "\"afterAgentResponse\"" "install-cursorhooks should configure afterAgentResponse"
assert_contains "$installed_hooks_json" "\"stop\"" "install-cursorhooks should configure stop"
assert_contains "$installed_hooks_json" "jai-cursorhooks before-submit" "install-cursorhooks should point to global hook command"
assert_not_contains "$installed_hooks_json" "JAI_DEBUG=true" "install-cursorhooks should not prepend debug env by default"

PATH="$SCRIPT_DIR:$PATH" JAI_DEBUG=true "$JAI" install-cursorhooks "$INSTALL_DIR_DEBUG" >/dev/null
debug_hooks_json="$(<"$INSTALL_DIR_DEBUG/.cursor/hooks.json")"
assert_contains "$debug_hooks_json" "JAI_DEBUG=true" "install-cursorhooks should prepend debug env when JAI_DEBUG=true"

rm -f "$TARGET"
hook_before_submit_output="$(CURSOR_PROJECT_DIR="/tmp/HOOKED" JAI_BIN="$JAI" JAI_TARGET="$TARGET" "$JAI_HOOKS" before-submit <<< '{"conversation_id":"9d3c096f-5f83-4a4d-bddd-73ff6b5fee79"}')"
assert_contains "$hook_before_submit_output" "\"continue\": true" "hook-before-submit should return continue=true"
assert_contains "$hook_before_submit_output" "\"JAI_PROJECT\": \"HOOKED\"" "hook-before-submit should export project env"
assert_contains "$hook_before_submit_output" "\"JAI_INDEX\": \"5fee79\"" "hook-before-submit should export conversation-based ref"
assert_contains "$hook_before_submit_output" "\"JAI_URL\": \"cursor://file//tmp/HOOKED/\"" "hook-before-submit should derive URL from project path"

hooked_running="$("$JAI" get -p "HOOKED" -i "5fee79" --target "$TARGET")"
assert_contains "$hooked_running" "HOOKED#5fee79: RUNNING" "hook-before-submit should create RUNNING task with conversation-based ref"

JAI_PROJECT="HOOKED" JAI_INDEX="5fee79" JAI_BIN="$JAI" JAI_TARGET="$TARGET" "$JAI_HOOKS" stop <<< '{}' >/dev/null
hooked_review="$("$JAI" get -p "HOOKED" -i "5fee79" --target "$TARGET")"
assert_contains "$hooked_review" "HOOKED#5fee79: REVIEW_REQUIRED - Cursor prompt submitted" "hook-stop should preserve current description"

rm -f "$TARGET"
CURSOR_PROJECT_DIR="/tmp/HOOKDESC" JAI_BIN="$JAI" JAI_TARGET="$TARGET" "$JAI_HOOKS" before-submit <<< '{"conversation_id":"11111111-1111-1111-1111-111111aaaaaa","description":"Implement retries for API gateway"}' >/dev/null
hooked_custom_desc="$("$JAI" get -p "HOOKDESC" -i "aaaaaa" --target "$TARGET")"
assert_contains "$hooked_custom_desc" "HOOKDESC#aaaaaa: RUNNING - Implement retries for API gateway" "hook-before-submit should use payload description when available"

# stop should still resolve when stdin payload is empty, using CURSOR_PROJECT_DIR + single RUNNING ref
JAI_PROJECT="" JAI_INDEX="" CURSOR_PROJECT_DIR="/tmp/HOOKDESC" JAI_BIN="$JAI" JAI_TARGET="$TARGET" "$JAI_HOOKS" stop <<< '' >/dev/null
hooked_custom_review="$("$JAI" get -p "HOOKDESC" -i "aaaaaa" --target "$TARGET")"
assert_contains "$hooked_custom_review" "HOOKDESC#aaaaaa: REVIEW_REQUIRED - Implement retries for API gateway" "hook-stop should preserve existing description when project is inferred"

# stop should prefer payload conversation ref over stale env JAI_INDEX
CURSOR_PROJECT_DIR="/tmp/HOOKPRIORITY" JAI_BIN="$JAI" JAI_TARGET="$TARGET" "$JAI_HOOKS" before-submit <<< '{"conversation_id":"22222222-2222-2222-2222-222222bbbbbb","description":"Payload priority task"}' >/dev/null
JAI_PROJECT="HOOKPRIORITY" JAI_INDEX="4" JAI_BIN="$JAI" JAI_TARGET="$TARGET" "$JAI_HOOKS" stop <<< '{"conversation_id":"22222222-2222-2222-2222-222222bbbbbb","workspace_roots":["/tmp/HOOKPRIORITY"]}' >/dev/null
hook_priority_review="$("$JAI" get -p "HOOKPRIORITY" -i "bbbbbb" --target "$TARGET")"
assert_contains "$hook_priority_review" "HOOKPRIORITY#bbbbbb: REVIEW_REQUIRED - Payload priority task" "hook-stop should preserve existing description and prefer payload conversation ref"

# unimplemented hooks should no-op and still append debug payload
debug_log_file="/tmp/jai/$(date +%F)-33333333-3333-3333-3333-333333cccccc.log"
rm -f "$debug_log_file"
JAI_DEBUG=true JAI_BIN="$JAI" JAI_TARGET="$TARGET" "$JAI_HOOKS" after-submit <<< '{"conversation_id":"33333333-3333-3333-3333-333333cccccc","message":"noop"}' >/dev/null
[[ -f "$debug_log_file" ]] || { printf 'FAIL: Expected debug payload log to be created for unimplemented hook\n' >&2; exit 1; }
debug_log_contents="$(<"$debug_log_file")"
assert_contains "$debug_log_contents" "\"message\":\"noop\"" "debug log should include raw payload for unimplemented hooks"

printf 'Phase 5 (install-cursorhooks + hook commands) passed.\n'

# Phase 6: optional URL should render linked markdown and persist across notify
rm -f "$TARGET"
link_idx="$("$JAI" start -p "CURSORLINK" -d "Open editor via deep link" -url "cursor://workspace/file?path=/tmp/file.sh" --target "$TARGET")"
[[ "$link_idx" == "0" ]] || { printf 'FAIL: Expected CURSORLINK start index 0, got %s\n' "$link_idx" >&2; exit 1; }

assert_file_contains "$TARGET" "- [CURSORLINK](cursor://workspace/file?path=/tmp/file.sh)#0: Open editor via deep link" "start with -url should render markdown link"

"$JAI" notify -p "CURSORLINK" -i "0" --target "$TARGET" >/dev/null
assert_file_contains "$TARGET" "- [CURSORLINK](cursor://workspace/file?path=/tmp/file.sh)#0: Open editor via deep link" "notify without -url should preserve existing url"

CURSOR_PROJECT_DIR="/tmp/LINKHOOK" JAI_BIN="$JAI" JAI_TARGET="$TARGET" "$JAI_HOOKS" before-submit <<< '{"conversation_id":"55555555-5555-5555-5555-555555eeffee","description":"Hook link task","url":"cursor://chat/open?conversation=55555555-5555-5555-5555-555555eeffee"}' >/dev/null
assert_file_contains "$TARGET" "- [LINKHOOK](cursor://chat/open?conversation=55555555-5555-5555-5555-555555eeffee)#eeffee: Hook link task" "hook-before-submit should persist payload url"

printf 'Phase 6 (URL deep links) passed.\n'

printf '\nAll verifications passed.\n\n'
printf 'Final target file contents:\n'
cat "$TARGET"
