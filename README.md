# JEG Claude Marketplace

Community plugin marketplace for Claude Code.

## Install the marketplace

```
claude plugin marketplace add https://github.com/Jorgeescribanogarcia/jeg-claude-marketplace
```

## Available Plugins

| Plugin | Description | Install |
|--------|-------------|---------|
| **cc-sync** | Backup and restore your Claude Code configuration to a private GitHub repo | `claude plugin install cc-sync@jeg` |

---

## Plugin Details

### cc-sync

Backup and restore your Claude Code configuration (settings, plugins, commands, skills, agents) to a private GitHub repository.

**Commands:**

| Command | Description |
|---|---|
| `/cc-setup` | First-time setup — configures GitHub token and MCP automatically |
| `/cc-backup` | Upload your configuration to GitHub |
| `/cc-restore` | Restore your configuration from GitHub |
| `/cc-status` | Show status and last backup date |

**Requirements:**
- Claude Code v22+
- A GitHub personal access token with `repo` scope (the `/cc-setup` command will guide you)

**Quick start:**

```
claude plugin install cc-sync@jeg
```

Restart Claude Code, then run:

```
/cc-setup
```

**Uninstall:**

```
claude plugin uninstall cc-sync@jeg
```

Your backups on GitHub (the `claude-code-config` repo) are not affected.

---

## Contributing

Want to add a plugin to this marketplace? Open a PR with your plugin inside the `plugins/` directory following the existing structure.

## Author

[Jorgeescribanogarcia](https://github.com/Jorgeescribanogarcia)
