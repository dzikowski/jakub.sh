# jakub.sh

A collection of utility tools for modern development workflows.

```
curl jakub.sh/install | bash
```

Installs all tools into `~/.local/bin`.

## jai

Allows to track progress of tasks/agents from multiple Cursor IDE windows and CLI sessions. You can install Cursor Hooks (note: it overrides existing hooks, and uses global if directory parameter is missing):

 (=> [README.md](jai/README.md)).

```bash
jai install-cursorhooks [directory]
```

Watch the progress:

```bash
jai watch
```

You can also open the markdown status file (`~/.local/jai-status.md`) in any tool that supports live-reloading from disk (like Typora, Obsidian, Cursor).


## sekey

Secure environment variable manager with automatic output sanitization (=> [README.md](sekey/README.md)).


Store a secret in macOS Keychain or Linux Secret Service. The script provides a masked prompt.

```bash
sekey set MY_SECRET
```

Sandbox the secret. The command is executed with env injected from secrets, and the output of the command is sanitized.

```bash
sekey --env MY_SECRET command.sh
```

