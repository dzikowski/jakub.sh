#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEKEY_SCRIPT="$SCRIPT_DIR/sekey.sh"

TEST_ENV_NAME="TEST_SEKEY_ENV_1"
TEST_ENV_VALUE="abc123"
TEST_ENV2_NAME="TEST_SEKEY_ENV_2"
TEST_ENV2_VALUE="xyz789"

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
  info "Cleaning up: Removing test env vars from Keychain"
  "$SEKEY_SCRIPT" delete "$TEST_ENV_NAME" >/dev/null 2>&1 || true
  "$SEKEY_SCRIPT" delete "$TEST_ENV2_NAME" >/dev/null 2>&1 || true
}

trap cleanup EXIT

echo "Testing sekey.sh functionality..."
echo ""

# Test 1: Add environment variable
info "Test 1: Adding $TEST_ENV_NAME to Keychain"
if output=$("$SEKEY_SCRIPT" set --value "$TEST_ENV_VALUE" "$TEST_ENV_NAME" 2>&1); then
  pass "Added $TEST_ENV_NAME to Keychain"
else
  fail "Failed to add $TEST_ENV_NAME to Keychain"
  echo "  Error: $output"
  exit 1
fi

# Verify it was added
set +e # Temporarily disable exit on error to capture exit code
"$SEKEY_SCRIPT" --env "$TEST_ENV_NAME" sh -c "[ -n \"\$$TEST_ENV_NAME\" ]" >/dev/null 2>&1
verify_result=$?
set -e # Re-enable exit on error
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
test_cmd="echo \"\$TEST_SEKEY_ENV_1 length is \${#TEST_SEKEY_ENV_1}\""
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

# Test 3: Two environment variables, stderr output, and error exit code
info "Test 3: Testing two env vars with stderr output and error exit code"

# Add second environment variable
if "$SEKEY_SCRIPT" set --value "$TEST_ENV2_VALUE" "$TEST_ENV2_NAME" >/dev/null 2>&1; then
  pass "Added $TEST_ENV2_NAME to Keychain"
else
  fail "Failed to add $TEST_ENV2_NAME to Keychain"
  exit 1
fi

# Execute command with both env vars, print to stderr, and exit with error
# Command prints both env vars to stderr and exits with code 42
# Note: Variables will be expanded by the inner shell when sh -c runs
set +e # Temporarily disable exit on error to capture exit code
output=$("$SEKEY_SCRIPT" --env "$TEST_ENV_NAME" --env "$TEST_ENV2_NAME" sh -c 'echo "Error: $TEST_SEKEY_ENV_1 and $TEST_SEKEY_ENV_2" >&2; exit 42' 2>&1)
exit_code=$?
set -e # Re-enable exit on error

# Verify exit code is passed through correctly
if [[ $exit_code -eq 42 ]]; then
  pass "Exit code correctly passed through: $exit_code"
else
  fail "Exit code not passed through correctly. Expected: 42, Got: $exit_code"
  exit 1
fi

# Verify stderr output is sanitized (both env values should be replaced with ***)
if echo "$output" | grep -q "\*\*\*"; then
  pass "Stderr output contains sanitized values"
else
  fail "Stderr output not sanitized"
  echo "  Output: $output"
  exit 1
fi

# Verify both actual values are NOT in the output
if echo "$output" | grep -q "$TEST_ENV_VALUE"; then
  fail "Secret value '$TEST_ENV_VALUE' leaked in stderr output!"
  echo "  Output: $output"
  exit 1
else
  pass "First secret value not present in stderr output"
fi

if echo "$output" | grep -q "$TEST_ENV2_VALUE"; then
  fail "Secret value '$TEST_ENV2_VALUE' leaked in stderr output!"
  echo "  Output: $output"
  exit 1
else
  pass "Second secret value not present in stderr output"
fi

# Verify both env vars appear in sanitized output
if echo "$output" | grep -q "Error: \*\*\* and \*\*\*"; then
  pass "Both env vars correctly sanitized in stderr output"
  info "  Actual output: $output"
else
  fail "Expected pattern 'Error: *** and ***' not found in output"
  echo "  Actual output: $output"
  exit 1
fi

echo ""

# Test 4: Remove both environment variables
info "Test 4: Removing both test env vars from Keychain"
if "$SEKEY_SCRIPT" delete "$TEST_ENV_NAME" >/dev/null 2>&1; then
  pass "Removed $TEST_ENV_NAME from Keychain"
else
  fail "Failed to remove $TEST_ENV_NAME from Keychain"
  exit 1
fi

if "$SEKEY_SCRIPT" delete "$TEST_ENV2_NAME" >/dev/null 2>&1; then
  pass "Removed $TEST_ENV2_NAME from Keychain"
else
  fail "Failed to remove $TEST_ENV2_NAME from Keychain"
  exit 1
fi

# Verify both were removed
if ! "$SEKEY_SCRIPT" --env "$TEST_ENV_NAME" sh -c "[ -n \"\$$TEST_ENV_NAME\" ]" >/dev/null 2>&1; then
  pass "Verified $TEST_ENV_NAME no longer exists in Keychain"
else
  fail "$TEST_ENV_NAME still exists in Keychain after deletion"
  exit 1
fi

if ! "$SEKEY_SCRIPT" --env "$TEST_ENV2_NAME" sh -c "[ -n \"\$$TEST_ENV2_NAME\" ]" >/dev/null 2>&1; then
  pass "Verified $TEST_ENV2_NAME no longer exists in Keychain"
else
  fail "$TEST_ENV2_NAME still exists in Keychain after deletion"
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
