#!/usr/bin/env bash

set -euo pipefail

VERSION="0.1.0"
KEYCHAIN_SERVICE="sekey-env"

# --- Helpers ---------------------------------------------------------------

error() {
  echo "❌ $*" >&2
  exit 1
}

validate_env_name() {
  local name="$1"
  [[ "$name" =~ ^[A-Z_][A-Z0-9_]*$ ]] ||
    error "Invalid ENV name '$name'. Use uppercase letters, digits and underscores only."
}

get_keychain_secret() {
  local env_name="$1"
  security find-generic-password \
    -a "$env_name" \
    -s "$KEYCHAIN_SERVICE" \
    -w 2>/dev/null || return 1
}

store_keychain_secret() {
  local env_name="$1"
  local value="$2"

  security add-generic-password \
    -a "$env_name" \
    -s "$KEYCHAIN_SERVICE" \
    -w "$value" \
    -U >/dev/null
}

delete_keychain_secret() {
  local env_name="$1"
  security delete-generic-password \
    -a "$env_name" \
    -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1 || true
}

escape_for_sed() {
  # Escape characters meaningful in sed replacement
  printf '%s' "$1" | sed -e 's/[\/&\\]/\\&/g'
}

sanitize_output() {
  local output="$1"
  shift
  local secrets=("$@")

  local sanitized="$output"

  for value in "${secrets[@]}"; do
    # Skip very short secrets to avoid over-masking
    if [[ ${#value} -lt 4 ]]; then
      continue
    fi

    local escaped
    escaped=$(escape_for_sed "$value")

    sanitized=$(printf '%s\n' "$sanitized" | sed "s/$escaped/***/g")
  done

  printf '%s' "$sanitized"
}

print_help() {
  cat <<EOF
Usage:
  $0 set [--value VALUE] ENV_NAME
  $0 delete ENV_NAME
  $0 --env ENV1 --env ENV2 CMD [ARGS...]
  $0 version
  $0 --help

Commands:
  set       Store secret in macOS Keychain
  delete    Remove secret from Keychain
  --env     Inject secrets into environment and sanitize output
  version   Show version
EOF
}

# --- Main ------------------------------------------------------------------

case "${1:-}" in

set)
  shift
  env_name=""
  value=""
  use_value_flag=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --value)
      [[ $# -ge 2 ]] || error "--value requires a value"
      value="$2"
      use_value_flag=true
      shift 2
      ;;
    *)
      [[ -z "$env_name" ]] || error "Usage: $0 set [--value VALUE] ENV_NAME"
      env_name="$1"
      shift
      ;;
    esac
  done

  [[ -n "$env_name" ]] || error "Usage: $0 set [--value VALUE] ENV_NAME"

  validate_env_name "$env_name"

  if [[ "$use_value_flag" == false ]]; then
    read -rsp "Enter value for ${env_name} (hidden): " value
    echo
  fi

  [[ -n "$value" ]] || error "Empty value not allowed"

  store_keychain_secret "$env_name" "$value"
  echo "✅ Stored ${env_name} in macOS Keychain"
  ;;

delete)
  [[ $# -ge 2 ]] || error "Usage: $0 delete ENV_NAME"
  env_name="$2"

  validate_env_name "$env_name"

  if ! get_keychain_secret "$env_name" >/dev/null 2>&1; then
    error "${env_name} not found in Keychain"
  fi

  delete_keychain_secret "$env_name"
  echo "✅ Deleted ${env_name}"
  ;;

--env | --env=*)
  declare -a env_names=()
  declare -a command_args=()
  declare -a secrets=()

  expect_env_value=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --env)
      expect_env_value=true
      shift
      ;;
    --env=*)
      env_names+=("${1#--env=}")
      shift
      ;;
    *)
      if [[ "$expect_env_value" == true ]]; then
        env_names+=("$1")
        expect_env_value=false
        shift
      else
        command_args+=("$@")
        break
      fi
      ;;
    esac
  done

  [[ "$expect_env_value" == false ]] || error "--env requires a variable name"
  [[ ${#env_names[@]} -gt 0 ]] || error "No environment variables specified"
  [[ ${#command_args[@]} -gt 0 ]] || error "No command specified"

  missing_envs=()

  for env_name in "${env_names[@]}"; do
    validate_env_name "$env_name"

    if value=$(get_keychain_secret "$env_name"); then
      export "$env_name=$value"
      secrets+=("$value")
    else
      missing_envs+=("$env_name")
    fi
  done

  if [[ ${#missing_envs[@]} -gt 0 ]]; then
    echo "❌ Missing environment variables:"
    for e in "${missing_envs[@]}"; do
      echo "   $e  →  $0 set $e"
    done
    exit 1
  fi

  # Execute command
  set +e
  output=$("${command_args[@]}" 2>&1)
  exit_code=$?
  set -e

  sanitized=$(sanitize_output "$output" "${secrets[@]}")
  printf '%s' "$sanitized"

  exit $exit_code
  ;;

version)
  echo "$VERSION"
  ;;

--help | -h | "")
  print_help
  ;;

*)
  error "Unknown command '$1'. Use --help."
  ;;
esac
