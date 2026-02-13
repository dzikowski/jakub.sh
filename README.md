# jakub.sh

A collection of utility tools for modern development workflows.

```
curl jakub.sh/install | bash
```

Installs all tools into `~/.local/bin`.


## sekey

Secure environment variable manager with automatic output sanitization (see [the readme](sekey/README.md)).

```bash
# Store a secret in macOS Keychain or Linux Secret Service (masked prompt)
sekey set MY_SECRET

# Sandbox the secret: It is injected for the command, and any appearances 
# in output are automatically sanitized
sekey --env MY_SECRET command.sh
```
