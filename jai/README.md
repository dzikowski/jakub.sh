# jai

Jai is the core workflow tool in this repo: it tracks agent/task progress across multiple Cursor IDE windows and CLI sessions in a shared markdown status file.

Default status file:

`~/.local/jai-status.md`

## What jai is for

Use Jai when you want one live source of truth for active work:

- Start or queue work from terminal scripts.
- Auto-update status from Cursor hooks during agent sessions.
- Watch progress in real time from any markdown viewer.

This keeps handoffs clear and prevents duplicated effort when several agents/sessions run in parallel.

## Quick start

```bash
# 1) Start tracking a task
jai start -p backend -d "Investigate flaky test"

# 2) Watch updates live
jai watch

# 3) Mark work as ready for review
jai notify -p backend -d "Done, ready for review"
```

## Commands

```bash
# Queue a new task (QUEUED, auto-assigns numeric index when -i omitted, prints id)
jai queue -p <project> -d <description> [-i <id>] [-url <url>] [--target <file>]

# Start a new task (RUNNING, auto-assigns numeric index when -i omitted, prints id)
jai start -p <project> -d <description> [-i <id>] [-url <url>] [--target <file>]

# Mark a task as review required (-d optional; reuses current description)
jai notify -p <project> [-d <description>] [-i <id>] [-url <url>] [--target <file>]

# Get status
jai get -p <project> [-i <id>] [--target <file>]

# Remove status entry
jai rm -p <project> [-i <id>] [--target <file>]

# Watch status file (refresh each second)
jai watch [--target <file>]

# Install Cursor hooks globally (default: ~)
jai install-cursorhooks [directory]
```

Allowed statuses:

- `QUEUED`
- `RUNNING`
- `REVIEW_REQUIRED`

## Task IDs

Task IDs are the `<id>` part of `project#id`.

- For manual `start`/`queue` without `-i`, JAI auto-assigns numeric ids (`0`, `1`, ...).
- For Cursor hooks, JAI uses the last 6 characters of `conversation_id` as id.

`queue` adds a new task as QUEUED, auto-assigns the next available numeric id, and prints it:

```bash
idx=$(jai queue -p agent-a -d "New sub-task")
echo "$idx"   # e.g. 3
```

`start` does the same but marks the task as RUNNING immediately:

```bash
idx=$(jai start -p agent-a -d "Investigating flaky test")
echo "$idx"   # e.g. 4
```

`notify` updates an id to REVIEW_REQUIRED. If `-i` is omitted, id `0` is used.  
If `-d` is omitted, the current description for that task id is reused:

```bash
jai notify -p agent-a -i 4 -d "Done, ready for review"
jai notify -p agent-a -d "Default index done"
jai notify -p agent-a -i 4
```

`stop` hook handling keeps the current task description when moving to `REVIEW_REQUIRED`.
If `-url` is omitted on `notify`, Jai keeps the existing task URL.

Without `-i`, `get` and `rm` affect all entries for that project (`project#...`).

## Deep links

Use optional `-url` to attach a URL (for example `cursor://...`) to a task:

```bash
jai start -p backend -d "Fix flaky test" -i 7 -url "cursor://chat/open?conversation=<id>"
```

In the markdown status file, Jai renders linked entries as:

```text
- **[backend](cursor://chat/open?conversation=<id>)#7**: Fix flaky test
```

Cursor hook integration derives `cursor://file/...` links from workspace/project path.
If a hook payload explicitly provides a URL field, Jai uses that as an override.

## Watch mode

Watch current status continuously:

```bash
jai watch
```

Use a custom file:

```bash
jai watch --target ./status.md
```

## Verification

Run end-to-end checks with:

```bash
jai/test.jai.sh
jai/test.jai-cursorhooks.sh
```

## Cursor hooks

Install hooks (global by default):

```bash
jai install-cursorhooks
```

Install hooks into a specific directory:

```bash
jai install-cursorhooks /path/to/workspace
```

This command writes:

- `<directory>/.cursor/hooks.json`

It expects `jai-cursorhooks` to be globally available in `PATH` (for example in `~/.local/bin`).

Configured hook actions:

- `beforeSubmitPrompt` -> `jai-cursorhooks before-submit` (starts/updates RUNNING with conversation-based id)
- `stop` -> `jai-cursorhooks stop` (moves task to REVIEW_REQUIRED without changing description)
- `afterAgentResponse` -> `jai-cursorhooks after-submit` (currently no-op)

Debug mode:

```bash
JAI_DEBUG=true jai install-cursorhooks
```

When installed this way, each hook command in `hooks.json` is prefixed with `JAI_DEBUG=true`.
At runtime in debug mode, hook payloads are appended to:

- `/tmp/jai/<YYYY-MM-DD>-<conversation_id>.log`

Unimplemented hooks intentionally do nothing (and only append payload logs in debug mode).
