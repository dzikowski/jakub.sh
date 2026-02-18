#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAI="$SCRIPT_DIR/jai.sh"
JAI_HOOKS="$SCRIPT_DIR/jai-cursorhooks.sh"
TARGET="$SCRIPT_DIR/.verify-cursorhooks-status.md"
TODAY="$(date +%F)"
DEBUG_CONVERSATION_ID="44444444-4444-4444-4444-444444dddddd"
DEBUG_LOG_FILE="/tmp/jai/${TODAY}-${DEBUG_CONVERSATION_ID}.log"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'FAIL: %s\nExpected to find: %s\n' "$msg" "$needle" >&2
    exit 1
  fi
}

assert_equals() {
  local actual="$1"
  local expected="$2"
  local msg="$3"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: %s\nExpected: %s\nActual:   %s\n' "$msg" "$expected" "$actual" >&2
    exit 1
  fi
}

cleanup() {
  rm -f "$TARGET" "$DEBUG_LOG_FILE"
}
trap cleanup EXIT

printf 'Running jai-cursorhooks verification...\n'
rm -f "$TARGET" "$DEBUG_LOG_FILE"

# 1) before-submit should create RUNNING entry and return env hints.
before_submit_output="$(
  CURSOR_PROJECT_DIR="/tmp/CURSORHOOKS" \
    JAI_BIN="$JAI" \
    JAI_TARGET="$TARGET" \
    "$JAI_HOOKS" before-submit <<< '{"conversation_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaa5ab321","description":"Prepare release notes"}'
)"
assert_contains "$before_submit_output" "\"continue\": true" "before-submit should return continue=true"
assert_contains "$before_submit_output" "\"JAI_PROJECT\": \"CURSORHOOKS\"" "before-submit should expose JAI_PROJECT"
assert_contains "$before_submit_output" "\"JAI_INDEX\": \"5ab321\"" "before-submit should expose conversation-based ref"
assert_contains "$before_submit_output" "\"JAI_URL\": \"cursor://file//tmp/CURSORHOOKS/\"" "before-submit should derive JAI_URL from project path"

running_status="$("$JAI" get -p "CURSORHOOKS" -i "5ab321" --target "$TARGET")"
assert_contains "$running_status" "CURSORHOOKS#5ab321: RUNNING - Prepare release notes" "before-submit should upsert RUNNING entry"

# 2) stop should move same task to REVIEW_REQUIRED.
JAI_PROJECT="CURSORHOOKS" JAI_INDEX="5ab321" JAI_BIN="$JAI" JAI_TARGET="$TARGET" "$JAI_HOOKS" stop <<< '{}' >/dev/null
review_status="$("$JAI" get -p "CURSORHOOKS" -i "5ab321" --target "$TARGET")"
assert_contains "$review_status" "CURSORHOOKS#5ab321: REVIEW_REQUIRED - Prepare release notes" "stop should mark task as review required without overriding description"

# 2b) before-submit with URL should render markdown deep link
before_submit_with_url="$(
  CURSOR_PROJECT_DIR="/tmp/CURSORHOOKSLINK" \
    JAI_BIN="$JAI" \
    JAI_TARGET="$TARGET" \
    "$JAI_HOOKS" before-submit <<< '{"conversation_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbb123abc","description":"Open deep link","url":"cursor://chat/open?conversation=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbb123abc"}'
)"
assert_contains "$before_submit_with_url" "\"JAI_URL\": \"cursor://chat/open?conversation=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbb123abc\"" "before-submit should propagate url payload"
target_contents="$(<"$TARGET")"
assert_contains "$target_contents" "- **[CURSORHOOKSLINK](cursor://chat/open?conversation=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbb123abc)#123abc**: Open deep link" "status file should render linked project format"

# 3) Unimplemented hooks should no-op and return empty JSON.
after_submit_output="$(JAI_BIN="$JAI" JAI_TARGET="$TARGET" "$JAI_HOOKS" after-submit <<< '{"conversation_id":"noop"}')"
assert_equals "$after_submit_output" "{}" "after-submit should be no-op"

unknown_output="$(JAI_BIN="$JAI" JAI_TARGET="$TARGET" "$JAI_HOOKS" unknown-action <<< '{"conversation_id":"noop"}')"
assert_equals "$unknown_output" "{}" "unknown action should be no-op"

# 4) In debug mode, payload should be appended to date+conversation log.
JAI_DEBUG=true JAI_BIN="$JAI" JAI_TARGET="$TARGET" "$JAI_HOOKS" after-submit <<< "{\"conversation_id\":\"${DEBUG_CONVERSATION_ID}\",\"message\":\"debug payload\"}" >/dev/null
[[ -f "$DEBUG_LOG_FILE" ]] || { printf 'FAIL: Expected debug log file %s\n' "$DEBUG_LOG_FILE" >&2; exit 1; }
debug_log_contents="$(<"$DEBUG_LOG_FILE")"
assert_contains "$debug_log_contents" "action=after-submit" "debug log should include hook action"
assert_contains "$debug_log_contents" "\"message\":\"debug payload\"" "debug log should include raw payload"

# 5) Hook should resolve jai directly from script directory.
rm -f "$TARGET"
default_resolution_output="$(
  PATH="/usr/bin:/bin" \
    CURSOR_PROJECT_DIR="/tmp/DIRECTJAI" \
    JAI_INDEX="deed12" \
    JAI_TARGET="$TARGET" \
    "$JAI_HOOKS" before-submit <<< '{"conversation_id":"cccccccc-cccc-cccc-cccc-ccccccdeed12","description":"Direct jai resolution"}'
)"
assert_contains "$default_resolution_output" "\"continue\": true" "before-submit should still run with stripped PATH"
directjai_status="$("$JAI" get -p "DIRECTJAI" -i "deed12" --target "$TARGET")"
assert_contains "$directjai_status" "DIRECTJAI#deed12: RUNNING" "hook should execute sibling jai.sh when JAI_BIN is unset"

printf 'jai-cursorhooks verification passed.\n'
