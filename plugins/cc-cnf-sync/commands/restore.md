# /restore

Restore your configuration from GitHub. Works on **Linux, macOS and Windows** (Git Bash).

## Steps to follow

### STEP 1 — Pre-flight checks

Run:
```bash
claude mcp list
```

**If GitHub MCP is NOT found**, stop and show:
```
❌ GitHub MCP not found.

Run /setup first to configure the GitHub MCP,
then restart Claude Code and run /restore again.
```

**If found**, continue.

---

### STEP 2 — Verify GitHub session

Call an **authenticated** GitHub MCP endpoint to confirm the session works — e.g.
`search_repositories` with query `user:@me` (or `get_me` if the server exposes it).
A merely *present* `github` MCP entry is NOT proof of a working session.

**If the call fails with an authentication error** (e.g. "Bad credentials") or the
MCP is not installed, stop and show:
```
❌ No active GitHub session.

Run /setup to configure your GitHub token,
then restart Claude Code and run /restore again.
```

**If authenticated**, save the username and continue.

---

### STEP 3 — Check backup repository exists

Use the GitHub MCP to check if `claude-code-config` exists for the authenticated user.

**If NOT found**, stop and show:
```
❌ Backup repository not found.

You haven't created a backup yet. Run /backup first.
```

**If found**, continue.

---

### STEP 4 — Show backup info and ask for confirmation

Use the GitHub MCP to read `backup-meta.json` from the repo and show:

```
📦 Backup found

  📅 Backup date: <backup_date>
  🖥️  Machine: <hostname>
  🔖 Claude Code version: <claude_version>
  🔗 Repository: https://github.com/<username>/claude-code-config

⚠️  This will overwrite your current configuration at:
    ~/.claude/

Continue with restore? (reply: yes / no)
```

Wait for user confirmation. If the user replies anything other than affirmative, stop.

---

### STEP 5 — Create a local safety backup

Before overwriting anything, back up the current config:

```bash
TS=$(date +%Y%m%d-%H%M%S)
SAFETY_BACKUP="$HOME/.claude-before-restore-$TS"
cp -r "$HOME/.claude" "$SAFETY_BACKUP"
echo "Safety backup created at: $SAFETY_BACKUP"
```

Show:
```
🛡️  Safety backup created at:
    ~/.claude-before-restore-<timestamp>
    (in case you need to roll back)
```

---

### STEP 6 — Download and restore files

Use the GitHub MCP to list all files in the `claude-code-config` repository.

For each file (excluding `backup-meta.json` **and** `plugins.json` — the latter is handled
in STEP 7):
1. Download the file content using the GitHub MCP
2. Determine the correct local path under `~/.claude/`
3. Create any necessary subdirectories
4. Write the file to the correct location

Mapping:
- `settings.json` → `~/.claude/settings.json`
- `CLAUDE.md` → `~/.claude/CLAUDE.md`
- `keybindings.json` → `~/.claude/keybindings.json`
- `commands/*` → `~/.claude/commands/`
- `skills/**` → `~/.claude/skills/`
- `agents/**` → `~/.claude/agents/`

> **Do NOT restore** `installed_plugins.json` or `known_marketplaces.json`. Older backups may
> still contain them; skip them if present. They hold absolute, machine-specific paths — the
> portable `plugins.json` (STEP 7) rebuilds plugins correctly for *this* machine instead.

Show progress as each file is restored.

---

### STEP 7 — Rebuild plugins from the portable manifest

If the repo contains `plugins.json`, use it to re-add marketplaces and reinstall plugins via
the Claude Code CLI. This regenerates the correct local paths and cache for **this** machine —
the whole point of the portable manifest.

1. Download `plugins.json` (via the GitHub MCP) and read its contents.
2. **First** add every marketplace (idempotent — ignore "already exists" errors), then
   install every plugin. Run these commands per entry (you are the agent — iterate over the
   manifest yourself; no shell JSON parsing needed):

```bash
# For each marketplace with a non-empty "add":
claude plugin marketplace add "<add>" --scope user

# Then, for each plugin:
claude plugin install "<id>" --scope user
# If that plugin had "enabled": false at backup time, also run:
claude plugin disable "<id>"
```

If `plugins.json` is **absent** (legacy backup made before this version), tell the user their
backup predates portable plugin sync and they should run `/backup` again after restoring, then
reinstall plugins manually with `claude plugin install <name>@<marketplace>`.

---

### STEP 8 — Final summary

```
✅ Restore completed

📁 Files restored: <count>
🔌 Plugins rebuilt: <n> plugin(s) from <m> marketplace(s)
📅 Backup applied: <backup_date>

⚠️  Restart Claude Code to apply all changes (plugins finish loading on restart).

🛡️  If something looks wrong, your previous config is at:
    ~/.claude-before-restore-<timestamp>
```
