# jakub.sh

A collection of utility tools for modern development workflows.

```
curl jakub.sh/install | bash
```

Installs all tools into `~/.local/bin`.


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

## jai

Task/agent status tracker (=> [README.md](jai/README.md)).

```bash
jai start -p api-agent -d "Implementing retries"
jai queue -p api-agent -d "New sub-task"
jai notify -p api-agent -i 5fee79
jai rm -p api-agent -i 1
jai get -p api-agent
jai watch
jai cursorhooks
```
