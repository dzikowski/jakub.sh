#!/usr/bin/env bash

set -euo pipefail

DEFAULT_TARGET="$HOME/.local/jai-status.md"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_ACTION="${1:-}"

resolve_jai_bin() {
  if [[ -n "${JAI_BIN:-}" ]]; then
    printf '%s' "$JAI_BIN"
    return 0
  fi

  if [[ -n "${JAI_SCRIPT_PATH:-}" ]]; then
    printf '%s' "$JAI_SCRIPT_PATH"
    return 0
  fi

  if [[ -x "$SCRIPT_DIR/jai.sh" ]]; then
    printf '%s' "$SCRIPT_DIR/jai.sh"
    return 0
  fi

  if [[ -x "$SCRIPT_DIR/jai" ]]; then
    printf '%s' "$SCRIPT_DIR/jai"
    return 0
  fi

  if command -v jai >/dev/null 2>&1; then
    command -v jai
    return 0
  fi

  printf 'jai'
}

JAI_BIN="$(resolve_jai_bin)"

normalize_text() {
  printf '%s' "$1" \
    | tr '\r\n\t' '   ' \
    | tr -cd '[:alnum:][:space:].,_@+:/-'
}

normalize_and_trim() {
  normalize_text "$1" | sed -E 's/[[:space:]]+/ /g; s/^ +//; s/ +$//'
}

normalize_url() {
  printf '%s' "$1" \
    | tr -d '\r\n\t ' \
    | tr -cd '[:alnum:][:punct:]'
}

encode_path_for_cursor_url() {
  local path="$1"
  path="${path// /%20}"
  path="${path//#/%23}"
  printf '%s' "$path"
}

build_cursor_url_from_path() {
  local path="$1"
  local encoded=""
  local normalized=""

  normalized="$(normalize_and_trim "$path")"
  [[ -n "$normalized" ]] || return 0

  encoded="$(encode_path_for_cursor_url "$normalized")"
  printf 'cursor://file/%s/' "$encoded"
}

read_hook_payload() {
  cat || true
}

jq_extract_string() {
  local hook_payload="$1"
  local jq_filter="$2"
  local extracted=""

  if [[ -z "${hook_payload//[[:space:]]/}" ]]; then
    printf ''
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    printf ''
    return 0
  fi

  extracted="$(printf '%s' "$hook_payload" | jq -r "$jq_filter" 2>/dev/null || true)"
  printf '%s' "$extracted"
}

extract_hook_description() {
  local hook_payload="$1"
  local extracted=""

  extracted="$(jq_extract_string "$hook_payload" '[.description?, .message?, .prompt?, .input?.text?, .request?.prompt?, .session?.initialPrompt?] | map(select(type == "string")) | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)) | .[0] // ""')"

  normalize_and_trim "$extracted"
}

extract_hook_conversation_id() {
  local hook_payload="$1"
  local extracted=""

  extracted="$(jq_extract_string "$hook_payload" '[.conversation_id?, .conversationId?, .conversation?.id?, .conversation?.conversation_id?, .conversation?.conversationId?, .request?.conversationId?, .request?.conversation_id?, .payload?.conversation_id?, .payload?.conversationId?] | map(select(type == "string")) | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)) | .[0] // ""')"

  normalize_and_trim "$extracted"
}

extract_hook_conversation_ref() {
  local hook_payload="$1"
  local extracted=""

  extracted="$(extract_hook_conversation_id "$hook_payload")"
  extracted="$(printf '%s' "$extracted" | tr -cd '[:alnum:]')"
  if [[ -n "$extracted" && ${#extracted} -gt 6 ]]; then
    extracted="${extracted: -6}"
  fi
  printf '%s' "$extracted"
}

extract_hook_workspace_project() {
  local hook_payload="$1"
  local extracted=""

  extracted="$(jq_extract_string "$hook_payload" '[.workspace_roots[]?, .workspaceRoots[]?, .request?.workspace_roots[]?, .request?.workspaceRoots[]?] | map(select(type == "string")) | map(gsub("/+$"; "")) | map(select(length > 0)) | map(split("/") | last) | .[0] // ""')"

  normalize_and_trim "$extracted"
}

extract_hook_workspace_root() {
  local hook_payload="$1"
  local extracted=""

  extracted="$(jq_extract_string "$hook_payload" '[.workspace_roots[]?, .workspaceRoots[]?, .request?.workspace_roots[]?, .request?.workspaceRoots[]?] | map(select(type == "string")) | map(gsub("/+$"; "")) | map(select(length > 0)) | .[0] // ""')"

  normalize_and_trim "$extracted"
}

extract_hook_url() {
  local hook_payload="$1"
  local extracted=""

  extracted="$(jq_extract_string "$hook_payload" '[.url?, .cursor_url?, .cursorUrl?, .deep_link?, .deepLink?, .link?, .session?.url?, .request?.url?, .request?.session?.url?] | map(select(type == "string")) | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)) | .[0] // ""')"

  normalize_url "$extracted"
}

resolve_single_running_ref() {
  local hook_target="$1"
  local project="$2"
  local refs=""
  local count=""

  [[ -f "$hook_target" ]] || return 0

  refs="$(
    awk -v base="$project" '
    function parse_token(raw,    line, marker_index, token, close_label, after_label, close_url, after_url, colon_idx, project_name, ref) {
      if (raw ~ /^- \*\*\[[^]]+\]\([^)]*\)(#[^:[:space:]]+)?\*\*: ?/) {
        line = raw
        sub(/^- \*\*\[/, "", line)
        close_label = index(line, "](")
        if (close_label <= 1) return ""
        project_name = substr(line, 1, close_label - 1)
        after_label = substr(line, close_label + 2)
        close_url = index(after_label, ")")
        if (close_url <= 0) return ""
        after_url = substr(after_label, close_url + 1)
        if (substr(after_url, 1, 1) == "#") {
          colon_idx = index(after_url, "**:")
          if (colon_idx <= 2) return ""
          ref = substr(after_url, 2, colon_idx - 2)
          return project_name "#" ref
        }
        if (substr(after_url, 1, 3) == "**:") {
          return project_name
        }
        return ""
      }
      if (raw ~ /^- \*\*[^*]+\*\*: ?/) {
        line = raw
        sub(/^- \*\*/, "", line)
        marker_index = index(line, "**:")
        if (marker_index <= 1) return ""
        token = substr(line, 1, marker_index - 1)
        return token
      }
      if (raw ~ /^- \[[^]]+\]\([^)]*\)(#[^:[:space:]]+)?: ?/) {
        line = raw
        sub(/^- \[/, "", line)
        close_label = index(line, "](")
        if (close_label <= 1) return ""
        project_name = substr(line, 1, close_label - 1)
        after_label = substr(line, close_label + 2)
        close_url = index(after_label, ")")
        if (close_url <= 0) return ""
        after_url = substr(after_label, close_url + 1)
        if (substr(after_url, 1, 1) == "#") {
          colon_idx = index(after_url, ":")
          if (colon_idx <= 2) return ""
          ref = substr(after_url, 2, colon_idx - 2)
          return project_name "#" ref
        }
        return project_name
      }
      return ""
    }
    /^# RUNNING$/ { section = "RUNNING"; next }
    /^# [A-Z_]+$/ { section = "OTHER"; next }
    {
      if (section != "RUNNING") next
      token = parse_token($0)
      if (token == "") next
      prefix = base "#"
      if (index(token, prefix) == 1 && length(token) > length(prefix)) {
        print substr(token, length(prefix) + 1)
      }
    }' "$hook_target"
  )"

  count="$(printf '%s\n' "$refs" | awk 'NF { c++ } END { print c + 0 }')"
  if [[ "$count" == "1" ]]; then
    printf '%s' "$(printf '%s\n' "$refs" | awk 'NF { print; exit }')"
  fi
}

resolve_single_running_project() {
  local hook_target="$1"
  local projects=""
  local count=""

  [[ -f "$hook_target" ]] || return 0

  projects="$(
    awk '
    function parse_token(raw,    line, marker_index, token, close_label, after_label, close_url, after_url, colon_idx, project_name, ref) {
      if (raw ~ /^- \*\*\[[^]]+\]\([^)]*\)(#[^:[:space:]]+)?\*\*: ?/) {
        line = raw
        sub(/^- \*\*\[/, "", line)
        close_label = index(line, "](")
        if (close_label <= 1) return ""
        project_name = substr(line, 1, close_label - 1)
        after_label = substr(line, close_label + 2)
        close_url = index(after_label, ")")
        if (close_url <= 0) return ""
        after_url = substr(after_label, close_url + 1)
        if (substr(after_url, 1, 1) == "#") {
          colon_idx = index(after_url, "**:")
          if (colon_idx <= 2) return ""
          ref = substr(after_url, 2, colon_idx - 2)
          return project_name "#" ref
        }
        if (substr(after_url, 1, 3) == "**:") {
          return project_name
        }
        return ""
      }
      if (raw ~ /^- \*\*[^*]+\*\*: ?/) {
        line = raw
        sub(/^- \*\*/, "", line)
        marker_index = index(line, "**:")
        if (marker_index <= 1) return ""
        token = substr(line, 1, marker_index - 1)
        return token
      }
      if (raw ~ /^- \[[^]]+\]\([^)]*\)(#[^:[:space:]]+)?: ?/) {
        line = raw
        sub(/^- \[/, "", line)
        close_label = index(line, "](")
        if (close_label <= 1) return ""
        project_name = substr(line, 1, close_label - 1)
        after_label = substr(line, close_label + 2)
        close_url = index(after_label, ")")
        if (close_url <= 0) return ""
        after_url = substr(after_label, close_url + 1)
        if (substr(after_url, 1, 1) == "#") {
          colon_idx = index(after_url, ":")
          if (colon_idx <= 2) return ""
          ref = substr(after_url, 2, colon_idx - 2)
          return project_name "#" ref
        }
        return project_name
      }
      return ""
    }
    /^# RUNNING$/ { section = "RUNNING"; next }
    /^# [A-Z_]+$/ { section = "OTHER"; next }
    {
      if (section != "RUNNING") next
      token = parse_token($0)
      if (token == "") next
      hash_index = index(token, "#")
      if (hash_index > 1) {
        print substr(token, 1, hash_index - 1)
      }
    }' "$hook_target" | awk '!seen[$0]++'
  )"

  count="$(printf '%s\n' "$projects" | awk 'NF { c++ } END { print c + 0 }')"
  if [[ "$count" == "1" ]]; then
    printf '%s' "$(printf '%s\n' "$projects" | awk 'NF { print; exit }')"
  fi
}

debug_log_payload_if_enabled() {
  local action="$1"
  local payload="$2"
  local conversation_id=""
  local date_prefix=""
  local safe_conversation=""
  local log_dir=""
  local log_path=""

  if [[ "${JAI_DEBUG:-}" != "true" ]]; then
    return 0
  fi

  conversation_id="$(extract_hook_conversation_id "$payload")"
  safe_conversation="$(printf '%s' "$conversation_id" | tr -cd '[:alnum:]_-')"
  if [[ -z "$safe_conversation" ]]; then
    safe_conversation="unknown"
  fi

  date_prefix="$(date +%F)"
  log_dir="/tmp/jai"
  log_path="${log_dir}/${date_prefix}-${safe_conversation}.log"
  mkdir -p "$log_dir"
  {
    printf 'time=%s action=%s\n' "$(date -u +%FT%TZ)" "$action"
    printf '%s\n\n' "$payload"
  } >>"$log_path"
}

run_before_submit() {
  local hook_target="$DEFAULT_TARGET"
  local project=""
  local index=""
  local start_description="Cursor prompt submitted"
  local payload_description=""
  local payload_project=""
  local payload_workspace_root=""
  local payload_ref=""
  local payload_url=""
  local hook_payload="$1"
  local additional_context=""

  payload_description="$(extract_hook_description "$hook_payload")"
  payload_project="$(extract_hook_workspace_project "$hook_payload")"
  payload_workspace_root="$(extract_hook_workspace_root "$hook_payload")"
  payload_ref="$(extract_hook_conversation_ref "$hook_payload")"
  payload_url="$(extract_hook_url "$hook_payload")"
  if [[ -n "$payload_description" ]]; then
    start_description="$payload_description"
  fi

  if [[ -n "${JAI_TARGET:-}" ]]; then
    hook_target="$JAI_TARGET"
  fi
  if [[ -n "${CURSOR_PROJECT_DIR:-}" ]]; then
    project="$(basename "$CURSOR_PROJECT_DIR")"
  fi
  if [[ -n "$payload_project" ]]; then
    project="$payload_project"
  fi
  if [[ -z "$payload_url" ]]; then
    if [[ -n "$payload_workspace_root" ]]; then
      payload_url="$(build_cursor_url_from_path "$payload_workspace_root")"
    elif [[ -n "${CURSOR_PROJECT_DIR:-}" ]]; then
      payload_url="$(build_cursor_url_from_path "$CURSOR_PROJECT_DIR")"
    fi
  fi
  project="$(normalize_and_trim "$project")"
  index="${payload_ref:-${JAI_INDEX:-0}}"

  if [[ -z "$project" ]]; then
    printf '{ "continue": true }\n'
    return 0
  fi

  if [[ -n "$payload_url" ]]; then
    index="$("$JAI_BIN" start -p "$project" -i "$index" -d "$start_description" -url "$payload_url" --target "$hook_target" 2>/dev/null || true)"
  else
    index="$("$JAI_BIN" start -p "$project" -i "$index" -d "$start_description" --target "$hook_target" 2>/dev/null || true)"
  fi
  if [[ -n "$index" ]]; then
    additional_context="JAI task auto-started as ${project}#${index}. Use 'jai queue' for extra tasks and keep descriptions concrete."
    printf '{ "continue": true, "env": { "JAI_PROJECT": "%s", "JAI_INDEX": "%s", "JAI_REF": "%s", "JAI_TARGET": "%s", "JAI_URL": "%s" }, "additional_context": "%s" }\n' \
      "$project" "$index" "$index" "$hook_target" "$payload_url" "$additional_context"
    return 0
  fi

  printf '{ "continue": true, "additional_context": "JAI auto-start failed. Run: REF=\$(jai start -p \"%s\" -i <id> -d \"<work description>\") and use that id for jai notify." }\n' "$project"
}

run_stop() {
  local hook_target="${JAI_TARGET:-$DEFAULT_TARGET}"
  local project="${JAI_PROJECT:-}"
  local index="${JAI_INDEX:-${JAI_REF:-}}"
  local hook_payload="$1"
  local payload_project=""
  local payload_workspace_root=""
  local payload_ref=""
  local payload_url=""

  payload_project="$(extract_hook_workspace_project "$hook_payload")"
  payload_workspace_root="$(extract_hook_workspace_root "$hook_payload")"
  payload_ref="$(extract_hook_conversation_ref "$hook_payload")"
  payload_url="$(extract_hook_url "$hook_payload")"

  if [[ -z "$project" && -n "${CURSOR_PROJECT_DIR:-}" ]]; then
    project="$(basename "$CURSOR_PROJECT_DIR")"
  fi
  if [[ -n "$payload_project" ]]; then
    project="$payload_project"
  fi
  if [[ -z "$payload_url" ]]; then
    if [[ -n "$payload_workspace_root" ]]; then
      payload_url="$(build_cursor_url_from_path "$payload_workspace_root")"
    elif [[ -n "${CURSOR_PROJECT_DIR:-}" ]]; then
      payload_url="$(build_cursor_url_from_path "$CURSOR_PROJECT_DIR")"
    fi
  fi
  if [[ -z "$project" ]]; then
    project="$(resolve_single_running_project "$hook_target")"
  fi
  project="$(normalize_and_trim "$project")"
  if [[ -n "$payload_ref" ]]; then
    index="$payload_ref"
  fi
  if [[ -z "$index" && -n "$project" ]]; then
    index="$(resolve_single_running_ref "$hook_target" "$project")"
  fi

  if [[ -n "$project" && -n "$index" ]]; then
    if [[ -n "$payload_url" ]]; then
      "$JAI_BIN" notify -p "$project" -i "$index" -url "$payload_url" --target "$hook_target" >/dev/null 2>&1 || true
    else
      "$JAI_BIN" notify -p "$project" -i "$index" --target "$hook_target" >/dev/null 2>&1 || true
    fi
  fi

  printf '{}\n'
}

run_noop() {
  printf '{}\n'
}

if [[ -z "$HOOK_ACTION" ]]; then
  run_noop
  exit 0
fi
shift || true

HOOK_PAYLOAD="$(read_hook_payload)"
debug_log_payload_if_enabled "$HOOK_ACTION" "$HOOK_PAYLOAD"

case "$HOOK_ACTION" in
before-submit)
  run_before_submit "$HOOK_PAYLOAD"
  ;;
stop)
  run_stop "$HOOK_PAYLOAD"
  ;;
before-start | session-start | after-submit | notify | pre-tool | post-tool | user-prompt)
  run_noop
  ;;
*)
  run_noop
  ;;
esac
