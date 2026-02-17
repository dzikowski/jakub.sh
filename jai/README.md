# jai

Track agent/task status in a shared markdown file.

Default status file:

`~/.local/jai-status.md`

## Commands

```bash
# Queue a new task (QUEUED, auto-assigns index, prints it)
jai queue -p <project> -d <description> [--target <file>]

# Start a new task (RUNNING, auto-assigns index, prints it)
jai start -p <project> -d <description> [--target <file>]

# Mark a task as review required
jai notify -p <project> -d <description> [-i <num>] [--target <file>]

# Get status
jai get -p <project> [-i <num>] [--target <file>]

# Remove status entry
jai rm -p <project> [-i <num>] [--target <file>]

# Watch status file (refresh each second)
jai watch [--target <file>]

# Print Cursor rule snippet
jai cursorrule
```

Allowed statuses:

- `QUEUED`
- `RUNNING`
- `REVIEW_REQUIRED`

## Indexed projects

`queue` adds a new task as QUEUED, auto-assigns the next available index, and prints it:

```bash
idx=$(jai queue -p agent-a -d "New sub-task")
echo "$idx"   # e.g. 3
```

`start` does the same but marks the task as RUNNING immediately:

```bash
idx=$(jai start -p agent-a -d "Investigating flaky test")
echo "$idx"   # e.g. 4
```

`notify` updates an index to REVIEW_REQUIRED. If `-i` is omitted, index `0` is used:

```bash
jai notify -p agent-a -i 4 -d "Done, ready for review"
jai notify -p agent-a -d "Default index done"
```

Without `-i`, `get` and `rm` affect all entries for that project (`project#N`).

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
