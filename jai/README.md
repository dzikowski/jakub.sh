# jai

Track agent/task status in a shared markdown file.

Default status file:

`~/.local/jai-status.md`

## Commands

```bash
# Queue a new task (QUEUED, auto-assigns numeric index when -i omitted, prints id)
jai queue -p <project> -d <description> [-i <id>] [--target <file>]

# Start a new task (RUNNING, auto-assigns numeric index when -i omitted, prints id)
jai start -p <project> -d <description> [-i <id>] [--target <file>]

# Mark a task as review required (-d optional; reuses current description)
jai notify -p <project> [-d <description>] [-i <id>] [--target <file>]

# Get status
jai get -p <project> [-i <id>] [--target <file>]

# Remove status entry
jai rm -p <project> [-i <id>] [--target <file>]

# Watch status file (refresh each second)
jai watch [--target <file>]

# Print global Cursor hooks JSON snippet
jai cursorhooks
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

`hook-stop` always sets a fixed review description (`Cursor session ended, review required`).

Without `-i`, `get` and `rm` affect all entries for that project (`project#...`).

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
```

## Cursor hooks

Install this output as `~/.cursor/hooks.json`:

```bash
jai cursorhooks > ~/.cursor/hooks.json
```

The generated global hooks call:

- `jai hook-before-submit` to upsert a RUNNING task on each prompt using `conversation_id` suffix (`last 6 chars`) as task id
- `jai hook-stop` to auto-notify REVIEW_REQUIRED for that same task when the session ends
