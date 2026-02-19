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



https://github.com/user-attachments/assets/c0ba3501-396d-4434-a4b3-c0b9bf3cd100



Allows to track progress of tasks/agents from multiple Cursor IDE windows and CLI sessions. Once you install Cursor Hooks, `jai` manages a single Markdown document with all current progress of agent sessions.

```bash
jai install-cursorhooks [directory]
```

Note Cursor Hooks will replace your existing ones. And if you don't provide the `directory` parameter, it will use the global one.

To see the status simply open the `~/.local/jai-status.md` file in any tool that supports live-reloading from disk (like Typora, Obsidian, Cursor). Or just do `jai watch` to have it the terminal.

&gt;&gt; [jai / README.md](jai/README.md) &lt;&lt;

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
&gt;&gt; [sekey / README.md](sekey/README.md) &lt;&lt;

