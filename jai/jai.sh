#!/usr/bin/env bash

set -euo pipefail

DEFAULT_TARGET="$HOME/.local/jai-status.md"
COMMAND="${1:-}"

print_help() {
  cat <<'EOF'
Usage:
  jai queue  -p <project> -d <description> [-i <id>] [--target <file>]
  jai start  -p <project> -d <description> [-i <id>] [--target <file>]
  jai notify -p <project> [-d <description>] [-i <id>] [--target <file>]
  jai get    -p <project> [-i <id>] [--target <file>]
  jai rm     -p <project> [-i <id>] [--target <file>]
  jai watch  [--target <file>]
  jai cursorhooks

'queue' adds a QUEUED entry; with no -i it auto-assigns the next numeric id and prints it.
'start' does the same but sets status to RUNNING.
'notify' sets an existing task to REVIEW_REQUIRED (defaults to id 0 when -i is omitted).
         If -d is omitted, notify reuses the current task description.
         Hook stop events pass their own description explicitly.

Statuses:
  QUEUED
  RUNNING
  REVIEW_REQUIRED
EOF
}

print_cursorhooks() {
  cat <<'EOF'
{
  "version": 1,
  "hooks": {
    "beforeSubmitPrompt": [
      {
        "command": "jai hook-before-submit"
      }
    ],
    "stop": [
      {
        "command": "jai hook-stop"
      }
    ]
  }
}
EOF
}

error() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

normalize_text() {
  printf '%s' "$1" \
    | tr '\r\n\t' '   ' \
    | tr -cd '[:alnum:][:space:].,_@+:/-'
}

normalize_and_trim() {
  normalize_text "$1" | sed -E 's/[[:space:]]+/ /g; s/^ +//; s/ +$//'
}

extract_hook_description() {
  local hook_payload="$1"
  local extracted=""

  if [[ -z "${hook_payload//[[:space:]]/}" ]]; then
    printf ''
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    extracted="$(
      HOOK_PAYLOAD="$hook_payload" python3 - <<'PY'
import json
import os

payload = os.environ.get("HOOK_PAYLOAD", "")
try:
    data = json.loads(payload)
except Exception:
    print("")
    raise SystemExit(0)

paths = [
    ("description",),
    ("message",),
    ("prompt",),
    ("input", "text"),
    ("request", "prompt"),
    ("session", "initialPrompt"),
]

current = None
for path in paths:
    value = data
    for key in path:
        if isinstance(value, dict) and key in value:
            value = value[key]
        else:
            value = None
            break
    if isinstance(value, str) and value.strip():
        current = value.strip()
        break

print(current or "")
PY
    )"
  fi

  normalize_and_trim "$extracted"
}

extract_hook_conversation_ref() {
  local hook_payload="$1"
  local extracted=""

  if [[ -z "${hook_payload//[[:space:]]/}" ]]; then
    printf ''
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    extracted="$(
      HOOK_PAYLOAD="$hook_payload" python3 - <<'PY'
import json
import os

payload = os.environ.get("HOOK_PAYLOAD", "")
try:
    data = json.loads(payload)
except Exception:
    print("")
    raise SystemExit(0)

paths = [
    ("conversation_id",),
    ("conversationId",),
    ("conversation", "id"),
    ("conversation", "conversation_id"),
    ("conversation", "conversationId"),
    ("request", "conversationId"),
    ("request", "conversation_id"),
    ("payload", "conversation_id"),
    ("payload", "conversationId"),
]

for path in paths:
    value = data
    for key in path:
        if isinstance(value, dict) and key in value:
            value = value[key]
        else:
            value = None
            break
    if isinstance(value, str) and value.strip():
        print(value.strip())
        raise SystemExit(0)

print("")
PY
    )"
  fi

  extracted="$(normalize_and_trim "$extracted" | tr -cd '[:alnum:]')"
  if [[ -n "$extracted" && ${#extracted} -gt 6 ]]; then
    extracted="${extracted: -6}"
  fi
  printf '%s' "$extracted"
}

extract_hook_workspace_project() {
  local hook_payload="$1"
  local extracted=""

  if [[ -z "${hook_payload//[[:space:]]/}" ]]; then
    printf ''
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    extracted="$(
      HOOK_PAYLOAD="$hook_payload" python3 - <<'PY'
import json
import os

payload = os.environ.get("HOOK_PAYLOAD", "")
try:
    data = json.loads(payload)
except Exception:
    print("")
    raise SystemExit(0)

root_paths = []
for key in ("workspace_roots", "workspaceRoots"):
    roots = data.get(key)
    if isinstance(roots, list):
        root_paths.extend(roots)

request = data.get("request")
if isinstance(request, dict):
    for key in ("workspace_roots", "workspaceRoots"):
        roots = request.get(key)
        if isinstance(roots, list):
            root_paths.extend(roots)

for first in root_paths:
    if isinstance(first, str) and first.strip():
        print(os.path.basename(first.rstrip("/")))
        raise SystemExit(0)

print("")
PY
    )"
  fi

  normalize_and_trim "$extracted"
}

run_hook_before_submit() {
  local hook_target="$DEFAULT_TARGET"
  local project=""
  local index=""
  local start_description="Cursor prompt submitted"
  local payload_description=""
  local payload_project=""
  local payload_ref=""
  local hook_payload=""
  local additional_context=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --target)
      [[ $# -ge 2 ]] || error "Missing value for $1"
      hook_target="$2"
      shift 2
      ;;
    --target=*)
      hook_target="${1#--target=}"
      shift
      ;;
    -h | --help)
      print_help
      exit 0
      ;;
    *)
      error "Unknown argument: $1"
      ;;
    esac
  done

  hook_payload="$(cat || true)"
  payload_description="$(extract_hook_description "$hook_payload")"
  payload_project="$(extract_hook_workspace_project "$hook_payload")"
  payload_ref="$(extract_hook_conversation_ref "$hook_payload")"
  if [[ -n "$payload_description" ]]; then
    start_description="$payload_description"
  fi

  if [[ -n "${CURSOR_PROJECT_DIR:-}" ]]; then
    project="$(basename "$CURSOR_PROJECT_DIR")"
  fi
  if [[ -n "$payload_project" ]]; then
    project="$payload_project"
  fi
  project="$(normalize_and_trim "$project")"
  index="${payload_ref:-${JAI_INDEX:-0}}"

  if [[ -z "$project" ]]; then
    printf '{ "continue": true }\n'
    return 0
  fi

  if index="$("$0" start -p "$project" -i "$index" -d "$start_description" --target "$hook_target" 2>/dev/null)"; then
    additional_context="JAI task auto-started as ${project}#${index}. Use 'jai queue' for extra tasks and keep descriptions concrete."
    printf '{ "continue": true, "env": { "JAI_PROJECT": "%s", "JAI_INDEX": "%s", "JAI_REF": "%s", "JAI_TARGET": "%s" }, "additional_context": "%s" }\n' \
      "$project" "$index" "$index" "$hook_target" "$additional_context"
    return 0
  fi

  printf '{ "continue": true, "additional_context": "JAI auto-start failed. Run: REF=$(jai start -p \"%s\" -i <id> -d \"<work description>\") and use that id for jai notify." }\n' "$project"
}

resolve_single_running_ref() {
  local hook_target="$1"
  local project="$2"
  local refs=""
  local count=""

  [[ -f "$hook_target" ]] || return 0

  refs="$(
    awk -v base="$project" '
    /^# RUNNING$/ { section = "RUNNING"; next }
    /^# [A-Z_]+$/ { section = "OTHER"; next }
    {
      if (section != "RUNNING") next
      if ($0 !~ /^- \*\*[^*]+\*\*: ?/) next
      line = $0
      sub(/^- \*\*/, "", line)
      marker_index = index(line, "**:")
      if (marker_index <= 1) next
      token = substr(line, 1, marker_index - 1)
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
    /^# RUNNING$/ { section = "RUNNING"; next }
    /^# [A-Z_]+$/ { section = "OTHER"; next }
    {
      if (section != "RUNNING") next
      if ($0 !~ /^- \*\*[^*]+\*\*: ?/) next
      line = $0
      sub(/^- \*\*/, "", line)
      marker_index = index(line, "**:")
      if (marker_index <= 1) next
      token = substr(line, 1, marker_index - 1)
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

run_hook_stop() {
  local hook_target="${JAI_TARGET:-$DEFAULT_TARGET}"
  local project="${JAI_PROJECT:-}"
  local index="${JAI_INDEX:-${JAI_REF:-}}"
  local notify_description="Cursor session ended, review required"
  local hook_payload=""
  local payload_project=""
  local payload_ref=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --target)
      [[ $# -ge 2 ]] || error "Missing value for $1"
      hook_target="$2"
      shift 2
      ;;
    --target=*)
      hook_target="${1#--target=}"
      shift
      ;;
    -h | --help)
      print_help
      exit 0
      ;;
    *)
      error "Unknown argument: $1"
      ;;
    esac
  done

  hook_payload="$(cat || true)"
  payload_project="$(extract_hook_workspace_project "$hook_payload")"
  payload_ref="$(extract_hook_conversation_ref "$hook_payload")"

  if [[ -z "$project" && -n "${CURSOR_PROJECT_DIR:-}" ]]; then
    project="$(basename "$CURSOR_PROJECT_DIR")"
  fi
  if [[ -n "$payload_project" ]]; then
    project="$payload_project"
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
    "$0" notify -p "$project" -i "$index" -d "$notify_description" --target "$hook_target" >/dev/null 2>&1 || true
  fi

  printf '{}\n'
}

validate_index() {
  local value="$1"
  [[ "$value" =~ ^[A-Za-z0-9_-]+$ ]] || error "Identifier must use only letters, digits, '_' or '-'."
}

build_project_token() {
  local base="$1"
  local idx="$2"
  if [[ -n "$idx" ]]; then
    printf '%s#%s' "$base" "$idx"
  else
    printf '%s' "$base"
  fi
}

project=""
status=""
description=""
index=""
target="$DEFAULT_TARGET"

if [[ "$COMMAND" == "--help" || "$COMMAND" == "-h" || -z "$COMMAND" ]]; then
  print_help
  exit 0
fi

if [[ "$COMMAND" == "cursorhooks" ]]; then
  print_cursorhooks
  exit 0
fi

if [[ "$COMMAND" == "hook-before-submit" ]]; then
  shift
  run_hook_before_submit "$@"
  exit 0
fi

if [[ "$COMMAND" == "hook-stop" ]]; then
  shift
  run_hook_stop "$@"
  exit 0
fi

if [[ "$COMMAND" == "watch" ]]; then
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --target)
      [[ $# -ge 2 ]] || error "Missing value for $1"
      target="$2"
      shift 2
      ;;
    --target=*)
      target="${1#--target=}"
      shift
      ;;
    -h | --help)
      print_help
      exit 0
      ;;
    *)
      error "Unknown argument: $1"
      ;;
    esac
  done

  if ! command -v watch >/dev/null 2>&1; then
    error "'watch' command not found."
  fi

  exec watch -n 1 cat "$target"
fi

if [[ "$COMMAND" != "queue" && "$COMMAND" != "start" && "$COMMAND" != "notify" && "$COMMAND" != "get" && "$COMMAND" != "rm" ]]; then
  error "Unknown command '$COMMAND'. Use --help."
fi
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
  -p | --project)
    [[ $# -ge 2 ]] || error "Missing value for $1"
    project="$2"
    shift 2
    ;;
  -s | --status)
    [[ $# -ge 2 ]] || error "Missing value for $1"
    status="$2"
    shift 2
    ;;
  -d | --description)
    [[ $# -ge 2 ]] || error "Missing value for $1"
    description="$2"
    shift 2
    ;;
  -i | --index)
    [[ $# -ge 2 ]] || error "Missing value for $1"
    index="$2"
    shift 2
    ;;
  --target)
    [[ $# -ge 2 ]] || error "Missing value for $1"
    target="$2"
    shift 2
    ;;
  --target=*)
    target="${1#--target=}"
    shift
    ;;
  -h | --help)
    print_help
    exit 0
    ;;
  *)
    error "Unknown argument: $1"
    ;;
  esac
done

project="$(normalize_and_trim "$project")"
[[ -n "$project" ]] || error "Project is required (-p)"
[[ -n "$index" ]] && validate_index "$index"

if [[ -n "$status" ]]; then
  error "The -s/--status option is no longer supported. Use queue/start/notify commands."
fi

if [[ "$COMMAND" == "notify" && -z "$index" ]]; then
  index="0"
fi

if [[ "$COMMAND" == "notify" ]]; then
  if [[ -n "$description" ]]; then
    description="$(normalize_and_trim "$description")"
    [[ -n "$description" ]] || error "Description cannot be empty."
  fi
  status="REVIEW_REQUIRED"
elif [[ "$COMMAND" == "queue" || "$COMMAND" == "start" ]]; then
  description="$(normalize_and_trim "$description")"
  [[ -n "$description" ]] || error "Description is required (-d)"
  if [[ "$COMMAND" == "queue" ]]; then
    status="QUEUED"
  else
    status="RUNNING"
  fi
fi

mkdir -p "$(dirname "$target")"

records_file="$(mktemp)"
deduped_file="$(mktemp)"
tmp_file="$(mktemp)"
filtered_file="$(mktemp)"

cleanup() {
  rm -f "$records_file" "$deduped_file" "$tmp_file" "$filtered_file"
}
trap cleanup EXIT

if [[ -f "$target" ]]; then
  awk '
  function normalize(value) {
    gsub(/\r|\n|\t/, " ", value)
    gsub(/[^[:alnum:][:space:].,_@+:\/#-]/, "", value)
    gsub(/[[:space:]]+/, " ", value)
    sub(/^ +/, "", value)
    sub(/ +$/, "", value)
    return value
  }
  /^# [A-Z_]+$/ {
    section = substr($0, 3)
    next
  }
  {
    if (section ~ /^(QUEUED|RUNNING|REVIEW_REQUIRED)$/ && $0 ~ /^- \*\*[^*]+\*\*: ?/) {
      line = $0
      sub(/^- \*\*/, "", line)
      marker_index = index(line, "**:")
      if (marker_index > 1) {
        project = normalize(substr(line, 1, marker_index - 1))
        description = normalize(substr(line, marker_index + 3))
        if (project != "" && description != "") {
          print project "\t" section "\t" description
        }
      }
    }
  }' "$target" >>"$records_file"
fi

if [[ ("$COMMAND" == "queue" || "$COMMAND" == "start") && -z "$index" ]]; then
  index=$(awk -F'\t' -v base="$project" '
  BEGIN { max = -1 }
  {
    token = $1
    prefix = base "#"
    if (index(token, prefix) == 1) {
      rest = substr(token, length(prefix) + 1)
      if (rest ~ /^[0-9]+$/) {
        idx = rest + 0
        if (idx > max) max = idx
      }
    }
  }
  END { print max + 1 }
  ' "$records_file")
fi

project_token="$(build_project_token "$project" "$index")"

if [[ "$COMMAND" == "notify" && -z "$description" ]]; then
  description="$(awk -F'\t' -v token="$project_token" '
  $1 == token { latest = $3; found = 1 }
  END {
    if (found) print latest
  }' "$records_file")"
  description="$(normalize_and_trim "$description")"
  [[ -n "$description" ]] || error "Description is required (-d) when there is no existing entry for '$project_token'."
fi

if [[ "$COMMAND" == "notify" || "$COMMAND" == "queue" || "$COMMAND" == "start" ]]; then
  printf '%s\t%s\t%s\n' "$project_token" "$status" "$description" >>"$records_file"
fi

awk -F'\t' '
{
  token = $1
  last[token] = NR
  row[NR] = $0
  key[NR] = token
}
END {
  for (i = 1; i <= NR; i++) {
    if (last[key[i]] == i) {
      print row[i]
    }
  }
}' "$records_file" >"$deduped_file"

if [[ "$COMMAND" == "get" ]]; then
  awk -F'\t' -v base="$project" -v idx="$index" '
  function matches(token, base, idx,    prefix, rest) {
    if (idx != "") {
      return token == (base "#" idx)
    }
    if (token == base) {
      return 1
    }
    prefix = base "#"
    if (index(token, prefix) == 1) {
      rest = substr(token, length(prefix) + 1)
      return rest != ""
    }
    return 0
  }
  matches($1, base, idx) { print $1 "\t" $2 "\t" $3 }' "$deduped_file" >"$filtered_file"

  if [[ ! -s "$filtered_file" ]]; then
    error "No entries found for project '$project'."
  fi

  LC_ALL=C sort -f "$filtered_file" | while IFS=$'\t' read -r token sec desc; do
    printf '%s: %s - %s\n' "$token" "$sec" "$desc"
  done
  exit 0
fi

if [[ "$COMMAND" == "rm" ]]; then
  awk -F'\t' -v base="$project" -v idx="$index" '
  function matches(token, base, idx,    prefix, rest) {
    if (idx != "") {
      return token == (base "#" idx)
    }
    if (token == base) {
      return 1
    }
    prefix = base "#"
    if (index(token, prefix) == 1) {
      rest = substr(token, length(prefix) + 1)
      return rest != ""
    }
    return 0
  }
  !matches($1, base, idx) { print $0 }' "$deduped_file" >"$filtered_file"
  mv "$filtered_file" "$deduped_file"
fi

for section in REVIEW_REQUIRED RUNNING QUEUED; do
  printf '# %s\n' "$section" >>"$tmp_file"

  awk -F'\t' -v sec="$section" '$2 == sec { print $1 "\t" $3 }' "$deduped_file" \
    | LC_ALL=C sort -f \
    | while IFS=$'\t' read -r entry_project entry_description; do
      printf -- '- **%s**: %s\n' "$entry_project" "$entry_description" >>"$tmp_file"
    done

  if [[ "$section" != "QUEUED" ]]; then
    printf '\n' >>"$tmp_file"
  fi
done

mv "$tmp_file" "$target"

if [[ "$COMMAND" == "rm" ]]; then
  if [[ -n "$index" ]]; then
    printf 'Removed %s from %s\n' "$project_token" "$target"
  else
    printf 'Removed all entries for %s from %s\n' "$project" "$target"
  fi
elif [[ "$COMMAND" == "queue" || "$COMMAND" == "start" ]]; then
  printf '%s\n' "$index"
else
  printf 'Updated %s (%s -> %s)\n' "$target" "$project_token" "$status"
fi
