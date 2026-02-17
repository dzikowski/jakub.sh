# jai

Track agent/task status in a shared markdown file.

Default status file:

`~/.local/jai/status.md`

## Commands

```bash
# Set status
jai set -p <project> -s <status> -d <description> [-i <num>] [--target <file>]

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

With index:

```bash
jai set -p agent-a -i 2 -s RUNNING -d "Investigating flaky test"
```

Stored line:

```md
- **agent-a#2**: Investigating flaky test
```

Without `-i`, `get` and `rm` affect all entries for that project (`project` and `project#N`).

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
