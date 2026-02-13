# sekey

Secure environment variable manager for macOS and Linux. Stores secrets in platform-native secure storage and injects them into command environments with automatic output sanitization.

## Usage

```bash
# Store a secret (will be prompted to enter the value securely)
sekey set MY_SECRET

# Sandboxing the secret: It is injected for the command, and any appearances 
# in output are automatically sanitized
sekey --env MY_SECRET echo "Secret is \$MY_SECRET"

# Multiple environment variables
sekey --env MY_SECRET --env ANOTHER_VAR command.sh

# Delete a stored secret
sekey delete MY_SECRET
```

## Installation

```bash
curl jakub.sh/install | bash
```

## Features

- **Secure storage**: macOS Keychain or Linux Secret Service
- **Output sanitization**: Automatically masks secrets in command output
- **Cross-platform**: Works on macOS and Linux
- **Simple API**: Store, delete, and inject secrets


## Requirements

- **macOS**: No additional dependencies
- **Linux**: `libsecret-tools` package
  ```bash
  # Ubuntu/Debian
  sudo apt-get install libsecret-tools
  
  # Fedora/RHEL
  sudo dnf install libsecret-tool
  
  # Arch
  sudo pacman -S libsecret
  ```

## Usage

### Store a secret

```bash
# Interactive (prompts for value)
sekey set API_KEY
```

### Delete a secret

```bash
sekey delete API_KEY
```

### Run command with secrets

```bash
# Single secret
sekey --env API_KEY curl -H "Authorization: Bearer \$API_KEY" https://api.example.com

# Multiple secrets
sekey --env API_KEY --env DB_PASSWORD --env TOKEN npm run deploy

# Alternative syntax
sekey --env=API_KEY --env=DB_PASSWORD npm run deploy
```

### Other commands

```bash
sekey version    # Show version
sekey --help     # Show help
```

## Rules

- Environment variable names must be uppercase letters, digits, and underscores only
- Variable names must start with a letter or underscore
- Empty values are not allowed
- Secrets shorter than 4 characters are not masked in output
