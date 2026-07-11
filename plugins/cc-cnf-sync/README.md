# cc-cnf-sync

Backup and restore your Claude Code configuration (settings, plugins, commands, skills, agents, and per-project memory) to a private GitHub repository.

Backups are **portable across machines**: instead of copying machine-specific plugin paths, `/export` writes a small `plugins.json` manifest (which plugins, from which marketplaces), and `/import` rebuilds them with the Claude Code CLI — so the same setup works under any username or OS.

**Per-project memory** (`~/.claude/projects/<project>/memory/*.md`) is kept in **continuous two-way sync across machines and operating systems**. Notes are keyed by a stable identity (the normalized **git remote URL**, falling back to the folder name) instead of the machine-specific path slug. `SessionStart` and `SessionEnd` hooks pull the latest from your backup, merge it with your local notes, and push your changes back — so every machine converges to the same set of notes whether the project lives at `D:\...\proj` on Windows or `/home/you/proj` on Linux. The merge is **conflict-safe**: if the same note diverged on two machines, both versions are kept (the second as `<name>.conflict.md`) and nothing is ever lost — git history in the backup is the safety net.

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
On every SessionStart/SessionEnd, for the project you have open:
  1. compute the project's git-remote key
  2. fetch the backup, reset to remote truth, file-level union-merge with local notes
  3. commit + push (retried if another machine pushed first)
  4. copy the merged result back into the local project
Result: open the project anywhere → its notes are there and up to date, both directions.
```

Merge rules (all lossless): a note that exists on only one side is copied to the other. For a note that
exists on both, the sync does a **3-way merge** against the version this machine last synced (the base):
if only one side changed, that edit wins with **no conflict** — so simply editing a note is never treated
as a conflict. Only when **both** sides changed the same note since the last sync are both copies kept
(`<name>.md` + `<name>.conflict.md`, compared ignoring CRLF/LF so line-endings alone never trigger it).
`MEMORY.md` (the index) is line-unioned.

Deletions are treated by kind. A plain `rm` of a **real note** does **not** propagate — it reappears from
the other machine — so an accidental delete is never silently mirrored everywhere. To remove a real note
**on purpose** (from the backup and every machine), use **`/memory delete <note>`**: it drops a
`<name>.md.deleted` tombstone the hook honors everywhere. A **`.conflict.md`** is an ephemeral marker, not
a note: once you reconcile it into `<name>.md` and delete it, that removal **also** propagates via a
`<name>.conflict.md.deleted` tombstone, so conflict files never pile up. (To bring a deleted note back,
remove its tombstone from `memory/<safeKey>/` in the backup.)

**Your global config rides along too.** Beyond per-project memory, the same hook continuously syncs your
user-level config — `CLAUDE.md`, `keybindings.json`, `settings.json`, `plugins.json`, and your
`commands/`, `skills/` and `agents/` folders — with the identical 3-way, conflict-safe logic. Edit your
global `CLAUDE.md` on one machine and it reaches the others automatically. It's a **strict allowlist**:
nothing else is ever touched, and anything machine-specific belongs in `settings.local.json`, which is
**never** synced (nor are `.credentials.json`, history, or tokens). A genuine two-sided edit of the same
config file keeps your local copy and saves the other version as a `.cc-conflict` sidecar.

Requirements on each machine: `git`, plus a git credential for `github.com` that the OS credential
helper already holds — git-credential-manager on Windows, `osxkeychain` on macOS, libsecret/store on
Linux, or `gh auth login`. **The hook needs no personal access token**: it pushes with git's normal
credentials (the same ones that let you `git push` your repos), so nothing expires out from under it in
an env var. It runs headless with `GIT_TERMINAL_PROMPT=0`, so a missing credential fails fast instead of
hanging. The hook is **fail-open** — if anything is missing or a push can't complete, your local notes
are left untouched, it tells you why, and it retries next session. On Windows it runs under Git Bash
(bundled with git); projects without a git remote fall back to a folder-name key.

## Commands

| Command | Description |
|---|---|
| `/setup` | First-time setup — configures GitHub token and MCP automatically |
| `/export` | Upload your configuration to GitHub |
| `/import` | Restore your configuration from GitHub |
| `/status` | Show status and last backup date |
| `/memory` | View and manage synced memory — list / view / delete notes without opening GitHub |
| `/uninstall` | Remove the plugin, saved token and (optionally) the GitHub MCP |

## Requirements

- Claude Code v22+
- Git Bash on Windows (Claude Code already requires it) — no extra setup on Linux/macOS
- A GitHub personal access token with `repo` scope (the `/setup` command will guide you)
- For the cross-machine memory hook: `git` on `PATH` (on Windows, Git Bash — bundled with Git) **and a working git credential for github.com** (its credential manager, or `gh auth login`). No PAT is needed for the hook — it uses git's own credentials. If either is missing, the hook simply does nothing; the rest of the plugin still works.

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
