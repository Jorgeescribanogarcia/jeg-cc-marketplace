# /backup

Upload your configuration to GitHub. Works on **Linux, macOS and Windows** (Git Bash).

## Steps to follow

### STEP 1 — Pre-flight checks

Run this command to check if the GitHub MCP is installed:

```bash
claude mcp list
```

Look for any entry containing "github" in the output.

**If GitHub MCP is NOT found**, stop and show:
```
❌ GitHub MCP not found.

Run /setup first to configure the GitHub MCP,
then restart Claude Code and run /backup again.
```

**If GitHub MCP IS found**, continue to Step 2.

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
then restart Claude Code and run /backup again.
```

**If authenticated**, save the username and continue.

---

### STEP 3 — Check or create backup repository

Use the GitHub MCP to check if a repository called `claude-code-config` exists for the authenticated user.

- If it does **NOT exist**: create it as a **private** repository with description:
  `Automated backup and restore of Claude Code configuration files (settings, plugins, commands, skills, agents) synced to a private GitHub repository.`
- If it **exists**: continue.

Show:
```
✅ GitHub MCP detected
✅ Active session as @<username>
✅ Repository: github.com/<username>/claude-code-config
```

---

### STEP 4 — Collect configuration files

Run the following `bash` to collect all config files into a temp directory. This works
on Linux, macOS and Windows (Git Bash), where `~/.claude` maps to the right place:

```bash
TS=$(date +%Y%m%d-%H%M%S)
TEMP_DIR="${TMPDIR:-/tmp}/claude-config-backup-$TS"
mkdir -p "$TEMP_DIR"

SOURCE="$HOME/.claude"

for f in settings.json CLAUDE.md keybindings.json; do
  [ -f "$SOURCE/$f" ] && cp "$SOURCE/$f" "$TEMP_DIR/$f"
done

for d in commands skills agents; do
  [ -d "$SOURCE/$d" ] && cp -r "$SOURCE/$d" "$TEMP_DIR/$d"
done

echo "$TEMP_DIR"
```

**IMPORTANT — Never include these files:**
- `.credentials.json`
- `settings.local.json`
- `history.jsonl`
- `~/.claude.json`
- Any file containing "token", "secret", or "key" in its name
- `plugins/installed_plugins.json` and `plugins/known_marketplaces.json` — these contain
  **absolute, machine-specific paths** (e.g. `/home/<you>/.claude/plugins/cache/...` or
  `C:\Users\<you>\.claude\plugins\cache\...`) and a local `cache/` that does not exist on
  other machines. They are intentionally replaced by the portable manifest generated in the
  next step.

---

### STEP 4b — Generate a portable plugin manifest

Instead of copying the machine-specific plugin JSONs, distill a portable manifest from the
Claude Code CLI. It records only *what* is installed and *which marketplace* it came from —
no absolute paths, no local cache dirs — so `/restore` can rebuild it on any machine/OS.

Run these two commands and read their JSON output:

```bash
claude plugin marketplace list --json
claude plugin list --json
```

Then **build `plugins.json` yourself** (you are the agent — construct the JSON directly from
the command output; do not rely on `jq`/`python` being installed) and write it to
`$TEMP_DIR/plugins.json` with this schema:

- `marketplaces[]`: one entry per marketplace with `name`, `source`, and `add`, where `add`
  is the source string that `claude plugin marketplace add` accepts:
  - github source → `"owner/repo"` (from the marketplace's `repo` field)
  - git source → the full clone URL (from the marketplace's `url` field)
- `plugins[]`: one entry per installed plugin with `id`, `scope`, and `enabled`.

The resulting `plugins.json` looks like:
```json
{
  "schema": 1,
  "marketplaces": [
    { "name": "claude-plugins-official", "source": "github", "add": "anthropics/claude-plugins-official" },
    { "name": "jeg", "source": "git", "add": "https://github.com/Jorgeescribanogarcia/jeg-cc-marketplace.git" }
  ],
  "plugins": [
    { "id": "cc-cnf-sync@jeg", "scope": "user", "enabled": true }
  ]
}
```

Upload `plugins.json` to the repo root alongside the other files.

---

### STEP 5 — Add metadata file

Create a file called `backup-meta.json` in the temp directory. Fill the fields from these
commands: `claude --version`, `uname -s` (OS, prints "Windows" if it fails), and `hostname`.

```json
{
  "backup_date": "<ISO timestamp>",
  "claude_version": "<output of: claude --version>",
  "os": "<Linux | Darwin | Windows>",
  "hostname": "<output of: hostname>"
}
```

---

### STEP 6 — Upload files to GitHub

Use the GitHub MCP to upload each collected file to the `claude-code-config` repository, preserving the directory structure.

Use this commit message:
```
backup: <date> - Claude Code config sync
```

Show progress as each file is uploaded.

---

### STEP 7 — Final summary

```
✅ Backup completed

📦 Files uploaded: <count>
🔗 Repository: https://github.com/<username>/claude-code-config
📅 Date: <timestamp>

Included:
  ✓ settings.json
  ✓ CLAUDE.md
  ✓ plugins.json (portable manifest — <n> plugins, <m> marketplaces)
  ✓ commands/ (<n> files)
  ✓ skills/ (<n> files)
  ✓ agents/ (<n> files)

Excluded for security:
  ⊘ .credentials.json
  ⊘ settings.local.json
  ⊘ history.jsonl
```
