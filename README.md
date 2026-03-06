# JEG Claude Marketplace

Community plugin marketplace for Claude Code.

## Install the marketplace

```
claude plugin marketplace add https://github.com/Jorgeescribanogarcia/jeg-claude-marketplace
```

## Available Plugins

| Plugin | Description | Install |
|--------|-------------|---------|
| **claude-config-sync** | Backup and restore your Claude Code configuration to a private GitHub repo | `claude plugin install claude-config-sync@jeg` |

---

## Plugin Details

### claude-config-sync

Backup and restore your Claude Code configuration (settings, plugins, commands, skills, agents) to a private GitHub repository.

**Commands:**

| Command | Description |
|---|---|
| `/setup-config-sync` | First-time setup — configures GitHub token and MCP automatically |
| `/backup-config` | Upload your configuration to GitHub |
| `/restore-config` | Restore your configuration from GitHub |
| `/config-status` | Show status and last backup date |

**Requirements:**
- Claude Code v22+
- A GitHub personal access token with `repo` scope (the `/setup-config-sync` command will guide you)

**Quick start:**

```
claude plugin install claude-config-sync@jeg
```

Restart Claude Code, then run:

```
/setup-config-sync
```

**Uninstall:**

```
claude plugin uninstall claude-config-sync@jeg
```

Your backups on GitHub (the `claude-code-config` repo) are not affected.

---

## Contributing

Want to add a plugin to this marketplace? Open a PR with your plugin inside the `plugins/` directory following the existing structure.

## Author

[Jorgeescribanogarcia](https://github.com/Jorgeescribanogarcia)
