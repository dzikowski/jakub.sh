#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEKEY_SCRIPT="$SCRIPT_DIR/sekey.sh"

TEST_ENV_NAME="TEST_SEKEY_ENV"
TEST_ENV_VALUE="abc123"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

test_passed=0
test_failed=0

pass() {
  echo -e "${GREEN}✓${NC} $1"
  test_passed=$((test_passed + 1))
}

fail() {
  echo -e "${RED}✗${NC} $1"
  test_failed=$((test_failed + 1))
}

info() {
  echo -e "${YELLOW}ℹ${NC} $1"
}

# Cleanup function
cleanup() {
  info "Cleaning up: Removing $TEST_ENV_NAME from Keychain"
  "$SEKEY_SCRIPT" delete "$TEST_ENV_NAME" >/dev/null 2>&1 || true
}

trap cleanup EXIT

echo "Testing sekey.sh functionality..."
echo ""

# Test 1: Add environment variable
info "Test 1: Adding $TEST_ENV_NAME to Keychain"
if "$SEKEY_SCRIPT" set --value "$TEST_ENV_VALUE" "$TEST_ENV_NAME" >/dev/null 2>&1; then
  pass "Added $TEST_ENV_NAME to Keychain"
else
  fail "Failed to add $TEST_ENV_NAME to Keychain"
  exit 1
fi

# Verify it was added
set +e  # Temporarily disable exit on error to capture exit code
"$SEKEY_SCRIPT" --env "$TEST_ENV_NAME" sh -c "[ -n \"\$$TEST_ENV_NAME\" ]" >/dev/null 2>&1
verify_result=$?
set -e  # Re-enable exit on error
if [[ $verify_result -eq 0 ]]; then
  pass "Verified $TEST_ENV_NAME exists in Keychain"
else
  fail "Failed to verify $TEST_ENV_NAME in Keychain (exit code: $verify_result)"
  exit 1
fi

echo ""

# Test 2: Verify env var is NOT in current shell environment and verify output sanitization
info "Test 2: Verifying $TEST_ENV_NAME is NOT in current shell environment and output sanitization"

# Check before running script
if [[ -n "${!TEST_ENV_NAME:-}" ]]; then
  fail "$TEST_ENV_NAME is present in current shell environment (before script)"
  exit 1
else
  pass "$TEST_ENV_NAME is not present in current shell environment (before script)"
fi

# Execute a command that uses the env var and capture output
# Note: Using ${#VAR} for character count (gives 6 for "abc123")
# The sanitization replaces the actual value with ***
test_cmd="echo \"\$TEST_SEKEY_ENV length is \${#TEST_SEKEY_ENV}\""
output=$("$SEKEY_SCRIPT" --env "$TEST_ENV_NAME" sh -c "$test_cmd" 2>&1)

# Check after running script
if [[ -n "${!TEST_ENV_NAME:-}" ]]; then
  fail "$TEST_ENV_NAME leaked into current shell environment (after script)"
  exit 1
else
  pass "$TEST_ENV_NAME is not present in current shell environment (after script)"
fi

# Verify output sanitization
expected_pattern="\*\*\* length is 6"
if echo "$output" | grep -q "$expected_pattern"; then
  pass "Output correctly sanitized: found '$expected_pattern'"
  info "  Actual output: $output"
else
  fail "Output sanitization failed"
  echo "  Expected pattern: $expected_pattern"
  echo "  Actual output: $output"
  exit 1
fi

# Verify the actual value is NOT in the output
if echo "$output" | grep -q "$TEST_ENV_VALUE"; then
  fail "Secret value '$TEST_ENV_VALUE' leaked in output!"
  echo "  Output: $output"
  exit 1
else
  pass "Secret value not present in output"
fi

echo ""

# Test 3: Remove environment variable
info "Test 4: Removing $TEST_ENV_NAME from Keychain"
if "$SEKEY_SCRIPT" delete "$TEST_ENV_NAME" >/dev/null 2>&1; then
  pass "Removed $TEST_ENV_NAME from Keychain"
else
  fail "Failed to remove $TEST_ENV_NAME from Keychain"
  exit 1
fi

# Verify it was removed
if ! "$SEKEY_SCRIPT" --env "$TEST_ENV_NAME" sh -c "[ -n \"\$$TEST_ENV_NAME\" ]" >/dev/null 2>&1; then
  pass "Verified $TEST_ENV_NAME no longer exists in Keychain"
else
  fail "$TEST_ENV_NAME still exists in Keychain after deletion"
  exit 1
fi

# Disable cleanup since we already deleted it
trap - EXIT

echo ""
echo "=========================================="
echo "Test Results:"
echo -e "  ${GREEN}Passed: $test_passed${NC}"
if [[ $test_failed -gt 0 ]]; then
  echo -e "  ${RED}Failed: $test_failed${NC}"
  exit 1
else
  echo -e "  ${GREEN}Failed: $test_failed${NC}"
  echo ""
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
fi
