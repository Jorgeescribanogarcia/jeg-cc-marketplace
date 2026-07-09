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

### STEP 4c — Local memory (opt-in)

Claude Code's persistent **local memory** lives under `~/.claude/projects/<slug>/memory/`
(each project has its own `memory/` folder with `MEMORY.md` plus individual fact files).
This is **not** the per-project `CLAUDE.md` files (those live inside each project's own repo)
— it's the machine-local memory Claude accumulates while you work.

**Ask the user first** (memory can contain personal notes, so it is opt-in):
```
🧠 Include local memory in this backup?

   This backs up ~/.claude/projects/*/memory/ (Claude's accumulated
   local memory), not the CLAUDE.md files of each project.

Include memory? (reply: yes / no)
```

**If the user replies no**, skip this step (do not collect any memory).

**If the user replies yes**, run this `bash` to collect every non-empty `memory/` folder,
preserving its project slug. Works on Linux, macOS and Windows (Git Bash):

```bash
SOURCE_PROJECTS="$HOME/.claude/projects"
MEM_DEST="$TEMP_DIR/memory"
mem_count=0
if [ -d "$SOURCE_PROJECTS" ]; then
  for pdir in "$SOURCE_PROJECTS"/*/; do
    mdir="${pdir}memory"
    if [ -d "$mdir" ] && [ -n "$(ls -A "$mdir" 2>/dev/null)" ]; then
      slug=$(basename "$pdir")
      mkdir -p "$MEM_DEST/$slug"
      cp -r "$mdir/." "$MEM_DEST/$slug/"
      mem_count=$((mem_count+1))
    fi
  done
fi
echo "Memory projects collected: $mem_count"
```

The collected `memory/<slug>/...` files will be uploaded together with the rest in STEP 6.

> **Note on portability:** the `<slug>` is the project's absolute path with slashes replaced
> by dashes (e.g. `/home/jorge/Escritorio/app` → `-home-jorge-Escritorio-app`). Memory
> re-attaches on restore only when the same project sits at the **same absolute path** on the
> destination machine (a different username or OS changes the slug). The backup/restore tooling
> itself is fully cross-platform.

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
  ✓ memory/ (<n> project(s))   ← only if the user opted in; omit this line otherwise

Excluded for security:
  ⊘ .credentials.json
  ⊘ settings.local.json
  ⊘ history.jsonl
```
