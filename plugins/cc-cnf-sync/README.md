# cc-cnf-sync

Backup and restore your Claude Code configuration (settings, plugins, commands, skills, agents) to a private GitHub repository.

Backups are **portable across machines**: instead of copying machine-specific plugin paths, `/backup` writes a small `plugins.json` manifest (which plugins, from which marketplaces), and `/restore` rebuilds them with the Claude Code CLI — so the same setup works under any username or OS.

**Cross-platform:** works on **Linux, macOS and Windows**. Everything runs through `bash`
(on Windows, Claude Code uses Git Bash), and `~/.claude` resolves to the right location on
every OS — no PowerShell required.

## Commands

| Command | Description |
|---|---|
| `/setup` | First-time setup — configures GitHub token and MCP automatically |
| `/backup` | Upload your configuration to GitHub |
| `/restore` | Restore your configuration from GitHub |
| `/status` | Show status and last backup date |
| `/uninstall` | Remove the plugin, saved token and (optionally) the GitHub MCP |

## Requirements

- Claude Code v22+
- Git Bash on Windows (Claude Code already requires it) — no extra setup on Linux/macOS
- A GitHub personal access token with `repo` scope (the `/setup` command will guide you)

## How setup works

`/setup` validates your GitHub token against the GitHub API **before** installing the
MCP, so an expired or wrong-scope token is caught up front instead of failing later.
If no valid token is found, it drops a `githubToken.sh` helper for you to paste one
in (keeping the secret out of the chat; the token is saved to `~/.config/cc-cnf-sync/token`
with `chmod 600`), then re-run `/setup`. After a successful setup, **restart Claude Code**
so the MCP reconnects with the new token.

## Quick start

```
claude plugin install cc-cnf-sync@jeg
```

Restart Claude Code, then run:

```
/setup
```

## Uninstall

Run the guided command, which also removes the saved token and (after asking) the GitHub MCP:

```
/uninstall
```

Or remove just the plugin manually:

```
claude plugin uninstall cc-cnf-sync@jeg
```

Your backups on GitHub (the `claude-code-config` repo) are not affected either way.

## License

This plugin is licensed under the [MIT License](LICENSE).
