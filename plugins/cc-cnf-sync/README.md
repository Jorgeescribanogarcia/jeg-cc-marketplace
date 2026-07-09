# cc-cnf-sync

Backup and restore your Claude Code configuration (settings, plugins, commands, skills, agents, and per-project memory) to a private GitHub repository.

Backups are **portable across machines**: instead of copying machine-specific plugin paths, `/backup` writes a small `plugins.json` manifest (which plugins, from which marketplaces), and `/restore` rebuilds them with the Claude Code CLI — so the same setup works under any username or OS.

**Per-project memory** (`~/.claude/projects/<project>/memory/*.md`) is also included, and it follows the project **across machines and operating systems**. Notes are keyed by a stable identity (the normalized **git remote URL**, falling back to the folder name) instead of the machine-specific path slug. A `SessionStart` hook then re-attaches each project's memory automatically the first time you open it on a new machine — pulling from your backup by that key — so the same project rehydrates its notes whether it lives at `D:\...\proj` on Windows or `/home/you/proj` on Linux.

Conversation transcripts (sessions) are intentionally **not** backed up — they're large and may contain sensitive pasted content.

**Cross-platform:** works on **Linux, macOS and Windows**. Everything runs through `bash`
(on Windows, Claude Code uses Git Bash), and `~/.claude` resolves to the right location on
every OS — no PowerShell required.

## What gets backed up

| Included | Excluded (for security / privacy) |
|---|---|
| `settings.json`, `CLAUDE.md`, `keybindings.json` | `.credentials.json`, `settings.local.json` |
| `commands/`, `skills/`, `agents/` | `history.jsonl`, `~/.claude.json` |
| `plugins.json` — portable plugin/marketplace manifest | Machine-specific plugin caches & absolute paths |
| Per-project memory (`projects/<project>/memory/`) | Session transcripts (`projects/*.jsonl`) |

### How cross-machine memory works

```
Machine A  /backup ─► GitHub (claude-code-config): memory/<key>/*.md + memory-manifest.json
Machine B  open project ─► SessionStart hook: computes the project's git-remote key,
                           clones the backup once, copies matching memory into the local
                           project — no manual step beyond having a token configured.
```

Requirements for the auto-attach hook on the target machine: `git`, `curl`, and a valid
`GITHUB_PERSONAL_ACCESS_TOKEN` (the same one `/setup` configures). The hook is **fail-open** — if
anything is missing it does nothing and never blocks your session. On Windows it runs under Git Bash
(bundled with git); projects without a git remote fall back to a folder-name key.

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
- For the cross-machine memory hook: `git` and `curl` on `PATH` (on Windows, Git Bash — bundled with Git — provides both). If missing, the hook simply does nothing; the rest of the plugin still works.

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
