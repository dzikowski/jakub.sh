#!/usr/bin/env bash

set -euo pipefail

VERSION="0.1.0"
DEFAULT_TARGET="$HOME/.local/jai-status.md"
COMMAND="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_help() {
  cat <<'EOF'
Usage:
  jai queue  -p <project> -d <description> [-i <id>] [-url <url>] [--target <file>]
  jai start  -p <project> -d <description> [-i <id>] [-url <url>] [--target <file>]
  jai notify -p <project> [-d <description>] [-i <id>] [-url <url>] [--target <file>]
  jai get    -p <project> [-i <id>] [--target <file>]
  jai rm     -p <project> [-i <id>] [--target <file>]
  jai watch  [--target <file>]
  jai install-cursorhooks [directory]
  jai version

'queue' adds a QUEUED entry; with no -i it auto-assigns the next numeric id and prints it.
'start' does the same but sets status to RUNNING.
'notify' sets an existing task to REVIEW_REQUIRED (defaults to id 0 when -i is omitted).
         If -d is omitted, notify reuses the current task description.
         Hook stop events pass their own description explicitly.

Statuses:
  QUEUED
  RUNNING
  REVIEW_REQUIRED

'install-cursorhooks' writes:
  <directory>/.cursor/hooks.json

directory defaults to '~' (your home directory).
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

normalize_url() {
  printf '%s' "$1" \
    | tr -d '\r\n\t ' \
    | tr -cd '[:alnum:][:punct:]'
}

expand_install_dir() {
  local raw="$1"

  if [[ "$raw" == "~" ]]; then
    printf '%s' "$HOME"
    return 0
  fi

  if [[ "$raw" == ~/* ]]; then
    printf '%s/%s' "$HOME" "${raw#~/}"
    return 0
  fi

  printf '%s' "$raw"
}

install_cursorhooks() {
  local install_root="${1:-~}"
  local expanded_root=""
  local cursor_dir=""
  local hooks_json=""
  local hook_command="jai-cursorhooks"
  local debug_prefix=""

  expanded_root="$(expand_install_dir "$install_root")"
  cursor_dir="$expanded_root/.cursor"
  hooks_json="$cursor_dir/hooks.json"

  if ! command -v jai-cursorhooks >/dev/null 2>&1 && [[ ! -f "$SCRIPT_DIR/jai-cursorhooks.sh" ]]; then
    error "Missing global hook script. Install jai-cursorhooks into PATH (recommended: ~/.local/bin)."
  fi
  mkdir -p "$cursor_dir"

  if [[ "${JAI_DEBUG:-}" == "true" ]]; then
    debug_prefix="env JAI_DEBUG=true "
  fi

  cat >"$hooks_json" <<EOF
{
  "version": 1,
  "hooks": {
    "beforeSubmitPrompt": [
      {
        "command": "${debug_prefix}${hook_command} before-submit"
      }
    ],
    "afterAgentResponse": [
      {
        "command": "${debug_prefix}${hook_command} after-submit"
      }
    ],
    "stop": [
      {
        "command": "${debug_prefix}${hook_command} stop"
      }
    ]
  }
}
EOF

  printf 'Installed cursor hooks to %s\n' "$cursor_dir"
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
url=""
target="$DEFAULT_TARGET"

if [[ "$COMMAND" == "--help" || "$COMMAND" == "-h" || -z "$COMMAND" ]]; then
  print_help
  exit 0
fi

if [[ "$COMMAND" == "version" ]]; then
  echo "$VERSION"
  exit 0
fi

if [[ "$COMMAND" == "install-cursorhooks" ]]; then
  shift
  if [[ $# -gt 1 ]]; then
    error "install-cursorhooks accepts at most one argument: [directory]"
  fi
  install_cursorhooks "${1:-~}"
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
  -url | --url)
    [[ $# -ge 2 ]] || error "Missing value for $1"
    url="$2"
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
if [[ -n "$url" ]]; then
  url="$(normalize_url "$url")"
  [[ -n "$url" ]] || error "URL cannot be empty after normalization."
fi

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
  function parse_old_entry(raw,    line, marker_index, token, desc) {
    if (raw !~ /^- \*\*[^*]+\*\*: ?/) return 0
    line = raw
    sub(/^- \*\*/, "", line)
    marker_index = index(line, "**:")
    if (marker_index <= 1) return 0
    parsed_token = normalize(substr(line, 1, marker_index - 1))
    parsed_desc = normalize(substr(line, marker_index + 3))
    parsed_url = ""
    return (parsed_token != "" && parsed_desc != "")
  }
  function parse_linked_entry(raw,    line, close_label, after_label, close_url, after_url, colon_idx, project_name, ref) {
    if (raw !~ /^- \[[^]]+\]\([^)]*\)(#[^:[:space:]]+)?: ?/) return 0
    line = raw
    sub(/^- \[/, "", line)
    close_label = index(line, "](")
    if (close_label <= 1) return 0
    project_name = normalize(substr(line, 1, close_label - 1))
    after_label = substr(line, close_label + 2)
    close_url = index(after_label, ")")
    if (close_url <= 0) return 0
    parsed_url = substr(after_label, 1, close_url - 1)
    after_url = substr(after_label, close_url + 1)
    if (substr(after_url, 1, 1) == "#") {
      colon_idx = index(after_url, ":")
      if (colon_idx <= 2) return 0
      ref = substr(after_url, 2, colon_idx - 2)
      parsed_token = normalize(project_name "#" ref)
      parsed_desc = normalize(substr(after_url, colon_idx + 1))
    } else if (substr(after_url, 1, 1) == ":") {
      parsed_token = normalize(project_name)
      parsed_desc = normalize(substr(after_url, 2))
    } else {
      return 0
    }
    return (parsed_token != "" && parsed_desc != "")
  }
  /^# [A-Z_]+$/ {
    section = substr($0, 3)
    next
  }
  {
    if (section !~ /^(QUEUED|RUNNING|REVIEW_REQUIRED)$/) next
    parsed_token = ""
    parsed_desc = ""
    parsed_url = ""
    if (parse_old_entry($0) || parse_linked_entry($0)) {
      print parsed_token "\t" section "\t" parsed_desc "\t" parsed_url
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

if [[ "$COMMAND" == "notify" && -z "$url" ]]; then
  url="$(awk -F'\t' -v token="$project_token" '
  $1 == token { latest = $4; found = 1 }
  END {
    if (found) print latest
  }' "$records_file")"
fi

if [[ "$COMMAND" == "notify" || "$COMMAND" == "queue" || "$COMMAND" == "start" ]]; then
  printf '%s\t%s\t%s\t%s\n' "$project_token" "$status" "$description" "$url" >>"$records_file"
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

  awk -F'\t' -v sec="$section" '$2 == sec { print $1 "\t" $3 "\t" $4 }' "$deduped_file" \
    | LC_ALL=C sort -f \
    | while IFS=$'\t' read -r entry_project entry_description entry_url; do
      if [[ -n "$entry_url" ]]; then
        entry_name="$entry_project"
        entry_ref=""
        if [[ "$entry_project" == *"#"* ]]; then
          entry_name="${entry_project%%#*}"
          entry_ref="${entry_project#*#}"
        fi
        if [[ -n "$entry_ref" && "$entry_ref" != "$entry_project" ]]; then
          printf -- '- [%s](%s)#%s: %s\n' "$entry_name" "$entry_url" "$entry_ref" "$entry_description" >>"$tmp_file"
        else
          printf -- '- [%s](%s): %s\n' "$entry_name" "$entry_url" "$entry_description" >>"$tmp_file"
        fi
      else
        printf -- '- **%s**: %s\n' "$entry_project" "$entry_description" >>"$tmp_file"
      fi
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
