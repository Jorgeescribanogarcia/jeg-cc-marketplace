# cc-cnf-sync

Backup and restore your Claude Code configuration (settings, plugins, commands, skills, agents) to a private GitHub repository.

Backups are **portable across machines**: instead of copying machine-specific plugin paths, `/backup` writes a small `plugins.json` manifest (which plugins, from which marketplaces), and `/restore` rebuilds them with the Claude Code CLI — so the same setup works under any username or OS.

## Commands

| Command | Description |
|---|---|
| `/setup` | First-time setup — configures GitHub token and MCP automatically |
| `/backup` | Upload your configuration to GitHub |
| `/restore` | Restore your configuration from GitHub |
| `/status` | Show status and last backup date |

## Requirements

- Claude Code v22+
- A GitHub personal access token with `repo` scope (the `/setup` command will guide you)

## How setup works

`/setup` validates your GitHub token against the GitHub API **before** installing the
MCP, so an expired or wrong-scope token is caught up front instead of failing later.
If no valid token is found, it drops a `githubToken.bat` helper for you to paste one
in (keeping the secret out of the chat), then re-run `/setup`. After a successful
setup, **restart Claude Code** so the MCP reconnects with the new token.

## Quick start

```
claude plugin install cc-cnf-sync@jeg
```

Restart Claude Code, then run:

```
/setup
```

## Uninstall

```
claude plugin uninstall cc-cnf-sync@jeg
```

Your backups on GitHub (the `claude-code-config` repo) are not affected.

## License

This plugin is licensed under the [MIT License](LICENSE).
