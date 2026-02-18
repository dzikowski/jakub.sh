# jakub.sh

A collection of utility tools for modern development workflows.

```bash
curl -fsSL https://jakub.sh/install | bash
```

Or if you want just some of the tools:

```bash
curl -fsSL https://jakub.sh/install | bash -s tool1,tool2
```

Installs all tools into `~/.local/bin`.

## jai

Allows to track progress of tasks/agents from multiple Cursor IDE windows and CLI sessions.

```bash
jai install-cursorhooks [directory]
```

Note Cursor Hooks will replace your existing ones. And if you don't provide the `directory` parameter, it will use the global one.

```bash
jai watch
```

The `watch` command is a simple wrapper to display and refresh the content of `jai` markdown document with updates. But you can also just open the `~/.local/jai-status.md` file in any tool that supports live-reloading from disk (like Typora, Obsidian, Cursor).

>> [jai/README.md](jai/README.md) <<

## sekey

Secure environment variable manager with automatic output sanitization.


Store a secret in macOS Keychain or Linux Secret Service. The script provides a masked prompt.

```bash
sekey set MY_SECRET
```

Sandbox the secret. The command is executed with env injected from secrets, and the output of the command is sanitized.

```bash
sekey --env MY_SECRET command.sh
```
>> [sekey/README.md](sekey/README.md) <<

