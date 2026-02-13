#!/usr/bin/env bash

set -euo pipefail

VERSION="0.1.0"
KEYCHAIN_SERVICE="sekey-env"

# --- Helper functions ---

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
  
  # Check if item exists first
  if security find-generic-password -a "$env_name" -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1; then
    # Item exists, update it
    security add-generic-password \
      -a "$env_name" \
      -s "$KEYCHAIN_SERVICE" \
      -w "$value" \
      -U 2>&1
  else
    # Item doesn't exist, add new
    security add-generic-password \
      -a "$env_name" \
      -s "$KEYCHAIN_SERVICE" \
      -w "$value" \
      2>&1
  fi
}

delete_keychain_secret() {
  local env_name="$1"
  security delete-generic-password \
    -a "$env_name" \
    -s "$KEYCHAIN_SERVICE" 2>/dev/null || true
}

sanitize_output() {
  local output="$1"
  shift
  local env_names=("$@")
  
  local sanitized="$output"
  
  for env_name in "${env_names[@]}"; do
    local value
    if value=$(get_keychain_secret "$env_name" 2>/dev/null); then
      # Escape special regex characters in the value
      local escaped_value
      escaped_value=$(printf '%s\n' "$value" | sed 's/[[\.*^$()+?{|]/\\&/g')
      # Replace actual value with masked version
      sanitized=$(printf '%s\n' "$sanitized" | sed "s|${escaped_value}|***|g")
    fi
  done
  
  printf '%s' "$sanitized"
}

# --- Main logic ---

case "${1:-}" in
  set)
    env_name=""
    value=""
    use_value_flag=false
    
    # Parse arguments
    shift
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --value)
          if [[ $# -lt 2 ]]; then
            echo "❌ --value requires a value"
            exit 1
          fi
          value="$2"
          use_value_flag=true
          shift 2
          ;;
        *)
          if [[ -z "$env_name" ]]; then
            env_name="$1"
          else
            echo "Usage: $0 set [--value VALUE] ENV_NAME"
            exit 1
          fi
          shift
          ;;
      esac
    done
    
    if [[ -z "$env_name" ]]; then
      echo "Usage: $0 add [--value VALUE] ENV_NAME"
      exit 1
    fi
    
    if [[ "$use_value_flag" == false ]]; then
      echo -n "Enter value for ${env_name} (input will be hidden): "
      read -rs value
      echo
    fi
    
    if [[ -z "$value" ]]; then
      echo "❌ Empty value not allowed"
      exit 1
    fi
    
    store_keychain_secret "$env_name" "$value"
    echo "✅ Stored ${env_name} in macOS Keychain"
    ;;
    
  delete)
    if [[ $# -lt 2 ]]; then
      echo "Usage: $0 delete ENV_NAME"
      exit 1
    fi
    
    env_name="$2"
    
    if ! get_keychain_secret "$env_name" >/dev/null 2>&1; then
      echo "⚠️  ${env_name} not found in Keychain"
      exit 1
    fi
    
    delete_keychain_secret "$env_name"
    echo "✅ Deleted ${env_name} from macOS Keychain"
    ;;
    
  --env|--env=*)
    # Parse --env flags: collect all --env args, then everything else is command
    env_names=()
    command_args=()
    i=1
    expect_env_value=false
    
    while [[ $i -le $# ]]; do
      arg="${!i}"
      
      if [[ "$expect_env_value" == true ]]; then
        # Previous was --env, this is the env name
        env_names+=("$arg")
        expect_env_value=false
        ((i++))
        continue
      fi
      
      case "$arg" in
        --env)
          expect_env_value=true
          ((i++))
          ;;
        --env=*)
          env_names+=("${arg#--env=}")
          ((i++))
          ;;
        *)
          # Everything from here on is the command
          while [[ $i -le $# ]]; do
            command_args+=("${!i}")
            ((i++))
          done
          break
          ;;
      esac
    done
    
    if [[ "$expect_env_value" == true ]]; then
      echo "❌ --env requires an environment variable name"
      exit 1
    fi
    
    if [[ ${#env_names[@]} -eq 0 ]]; then
      echo "❌ No environment variables specified. Use --env ENV_NAME"
      exit 1
    fi
    
    if [[ ${#command_args[@]} -eq 0 ]]; then
      echo "❌ No command specified"
      exit 1
    fi
    
    # Load env vars from Keychain
    missing_envs=()
    for env_name in "${env_names[@]}"; do
      value=""
      if value=$(get_keychain_secret "$env_name" 2>/dev/null); then
        export "$env_name=$value"
      else
        missing_envs+=("$env_name")
      fi
    done
    
    if [[ ${#missing_envs[@]} -gt 0 ]]; then
      echo "❌ Missing environment variables in Keychain: ${missing_envs[*]}"
      echo "   Use '$0 set ${missing_envs[0]}' to set them"
      exit 1
    fi
    
    # Execute command and capture output
    cmd="${command_args[0]}"
    cmd_args=("${command_args[@]:1}")
    
    # Capture both stdout and stderr, preserving exit code
    # Temporarily disable set -e to capture output even if command fails
    set +e
    output=""
    exit_code=0
    
    # Handle empty cmd_args array safely with set -u
    if [[ ${#cmd_args[@]} -gt 0 ]]; then
      output=$("$cmd" "${cmd_args[@]}" 2>&1)
    else
      output=$("$cmd" 2>&1)
    fi
    exit_code=$?
    set -e
    
    # Sanitize output
    sanitized_output=""
    sanitized_output=$(sanitize_output "$output" "${env_names[@]}")
    
    # Print sanitized output
    printf '%s' "$sanitized_output"
    
    exit $exit_code
    ;;
    
  version)
    echo "$VERSION"
    exit 0
    ;;
    
  *)
    echo "Usage:"
    echo "  $0 set ENV_NAME              - Set environment variable in Keychain"
    echo "  $0 delete ENV_NAME           - Remove environment variable from Keychain"
    echo "  $0 --env ENV1 --env ENV2 CMD - Execute CMD with env vars, sanitize output"
    echo "  $0 version                   - Show version"
    exit 1
    ;;
esac
