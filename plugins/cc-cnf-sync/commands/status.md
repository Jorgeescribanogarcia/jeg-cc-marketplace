# /status

Show current Claude Code configuration status and last backup information.

## Steps to follow

### STEP 1 — Gather local information

```bash
# Claude Code version
claude --version

# Installed plugins
claude plugin list

# GitHub CLI authentication (this is how cc-cnf-sync authenticates — no MCP)
gh auth status --hostname github.com 2>&1 | head -5
```

---

### STEP 2 — Check last backup on GitHub

If `gh` is authenticated, capture the username (`gh api user --jq .login`) and read the backup
metadata straight from the repo (raw, no clone needed):

```bash
gh api "repos/<username>/claude-code-config/contents/backup-meta.json" \
  -H "Accept: application/vnd.github.raw" 2>/dev/null
gh api "repos/<username>/claude-code-config/contents/memory-manifest.json" \
  -H "Accept: application/vnd.github.raw" 2>/dev/null
```

- From `backup-meta.json` extract `backup_date`, `hostname`, `claude_version`.
- From `memory-manifest.json` sum `projects[].files` for a note count (treat as 0 / "—" if absent).
- If either call fails because the repo/file doesn't exist yet, treat that value as "Never" / "—".

If `gh` is not installed or not authenticated:
- Show: `Could not connect to GitHub — run /setup first`

---

### STEP 3 — Display status

```
📊 Configuration Status — Claude Code

🖥️  Local version: <claude --version>
📁 Config path: ~/.claude/

INSTALLED PLUGINS:
  <list from claude plugin list>

GITHUB AUTH:
  <@username via gh, or "not signed in — run /setup">

LAST GITHUB BACKUP:
  📅 Date: <backup_date or "Never">
  🖥️  Machine: <hostname or "—">
  🔖 Version: <claude_version or "—">
  🧠 Memory: <k note(s) across n project(s), or "—">
  🔗 Repo: https://github.com/<username>/claude-code-config

DAYS SINCE LAST BACKUP: <days or "N/A">
```

If more than 7 days have passed since the last backup, show:
```
⚠️  It has been more than 7 days since your last backup.
    Run /export to update it.
```
