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
- Session transcripts — `projects/<slug>/*.jsonl` (and any other files directly under a project
  dir). These are large and may contain secrets pasted into the chat. Only each project's
  `memory/` subfolder is backed up (STEP 4c), never the raw sessions.

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

### STEP 4c — Collect per-project memory (keyed by a portable, OS-independent identity)

Persistent memory is **per project**: it lives at `~/.claude/projects/<slug>/memory/*.md`, where
`<slug>` is the project's absolute path with separators replaced. That slug is path- and OS-specific
(Windows `D--...-marketplace` ≠ Linux `-home-jorge-marketplace`), so keying by slug alone can't
follow the project to another machine. Instead we key each project's memory by a **stable identity**:
the normalized **git remote URL** (identical on every clone/OS), falling back to the folder name.

The `SessionStart` hook (`hooks/attach-memory.sh`) recomputes this same key on the target machine and
re-attaches the memory automatically. Run this `bash` (works on Linux, macOS and Windows via Git Bash);
the key rules **must stay identical** to `norm_key()` in `hooks/attach-memory.sh`:

> **Before running the script**, download the repo's current `memory-manifest.json` (via the
> GitHub MCP) to `$TEMP_DIR/prev-manifest.json` if it exists. It lets this backup detect when a
> project's key changed (e.g. the repo was renamed) and leave a rename alias so old clones keep
> resolving. If the repo has no manifest yet, skip the download — the script handles its absence.

```bash
SOURCE_PROJECTS="$HOME/.claude/projects"
MEM_DEST="$TEMP_DIR/memory"

# Normalize a git remote (or folder name) into an OS-independent key.
# MUST stay identical to norm_key() in hooks/attach-memory.sh.
norm_key() {
  k=$1
  case "$k" in *.git) k=${k%.git} ;; esac
  case "$k" in *@*:*) host=${k#*@}; host=${host%%:*}; path=${k#*:}; k="$host/$path" ;; esac
  k=$(printf '%s' "$k" | sed -E 's#^[a-zA-Z]+://##; s#^[^@/]*@##')
  printf '%s' "$k" | tr 'A-Z' 'a-z'
}

entries=""
count=0
if [ -d "$SOURCE_PROJECTS" ]; then
  for pdir in "$SOURCE_PROJECTS"/*/; do
    mdir="${pdir}memory"
    [ -d "$mdir" ] || continue
    [ -n "$(find "$mdir" -type f 2>/dev/null | head -n1)" ] || continue
    fcount=$(find "$mdir" -type f 2>/dev/null | wc -l | tr -d ' ')
    slug=$(basename "$pdir")

    # Recover the project's real cwd from ANY session transcript (the slug can't be reversed
    # reliably, and the first .jsonl may be a summary sidecar with no cwd — so scan them all).
    cwd=$(sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$pdir"*.jsonl 2>/dev/null | head -n1)
    cwd=$(printf '%s' "$cwd" | sed 's#\\\\#\\#g' | tr '\\' '/')

    key=""
    if [ -n "$cwd" ]; then
      remote=$(git -C "$cwd" remote get-url origin 2>/dev/null)
      if [ -n "$remote" ]; then
        key=$(norm_key "$remote")
      else
        key="local/$(basename "$cwd" | tr 'A-Z' 'a-z')"
      fi
    fi
    [ -n "$key" ] || key="slug/$(printf '%s' "$slug" | tr 'A-Z' 'a-z')"   # last resort
    safe=$(printf '%s' "$key" | sed 's/[^a-z0-9._-]/-/g')
    if [ -n "$cwd" ]; then name=$(basename "$cwd"); else name=$slug; fi

    mkdir -p "$MEM_DEST/$safe"
    cp -r "$mdir/." "$MEM_DEST/$safe/"

    # Rename-robustness: if a previous backup keyed THIS project (matched by slug — stable on
    # the same machine) under a DIFFERENT safeKey, the repo was likely renamed. Drop a sidecar
    # `memory/<oldSafeKey>.alias` (one line = the current safeKey) so a clone that still computes
    # the old key keeps resolving to the up-to-date notes. Read by norm_key()'s companion logic
    # in hooks/attach-memory.sh.
    if [ -f "$TEMP_DIR/prev-manifest.json" ]; then
      prevsafe=$(grep -F "\"slug\": \"$slug\"" "$TEMP_DIR/prev-manifest.json" 2>/dev/null \
                 | sed -n 's/.*"safeKey"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
      if [ -n "$prevsafe" ] && [ "$prevsafe" != "$safe" ]; then
        printf '%s\n' "$safe" > "$MEM_DEST/$prevsafe.alias"
      fi
    fi

    [ -n "$entries" ] && entries="$entries,"
    entries="$entries
    { \"slug\": \"$slug\", \"key\": \"$key\", \"safeKey\": \"$safe\", \"name\": \"$name\", \"files\": $fcount }"
    count=$((count+1))
  done
fi

printf '{\n  "schema": 2,\n  "projects": [%s\n  ]\n}\n' "$entries" > "$TEMP_DIR/memory-manifest.json"
echo "Memory: $count project(s) collected."
```

This writes each project's notes to `memory/<safeKey>/...` in the temp dir plus a
`memory-manifest.json` at the root, e.g.:
```json
{
  "schema": 2,
  "projects": [
    {
      "slug": "D--Windows-Usuarios-Elmister180-Escritorio-jeg-agents-marketplace",
      "key": "github.com/jorgeescribanogarcia/jeg-agents-marketplace",
      "safeKey": "github.com-jorgeescribanogarcia-jeg-agents-marketplace",
      "name": "jeg-agents-marketplace",
      "files": 3
    }
  ]
}
```

Upload the `memory/` tree (including any `<oldSafeKey>.alias` sidecars) and `memory-manifest.json`
to the repo alongside the other files. The upload is **additive** — do NOT delete `memory/` folders
that exist in the repo but not in this backup: they belong to other machines' projects or to a
project's previous name, and pruning them would break those clones.

> **Portability:** because memory is keyed by the git remote (not the path), the `SessionStart` hook
> can re-attach it on any machine/OS where the same repo is checked out — regardless of where it lives
> on disk. Projects with no git remote fall back to a folder-name key (works if the folder name matches).
>
> **Repo renames:** renaming a repo changes its normalized key, so a fresh clone would compute a new
> key with no folder. To survive that, a backup that detects a project's key changed (same slug, new
> safeKey) writes a `memory/<oldSafeKey>.alias` sidecar pointing at the current key; the hook follows
> it, so clones on either the old or new remote keep resolving to the same, up-to-date notes.

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
  ✓ memory/ (<n> project(s), <k> notes)
  ✓ commands/ (<n> files)
  ✓ skills/ (<n> files)
  ✓ agents/ (<n> files)
  ✓ memory/ (<n> project(s))   ← only if the user opted in; omit this line otherwise

Excluded for security:
  ⊘ .credentials.json
  ⊘ settings.local.json
  ⊘ history.jsonl
  ⊘ session transcripts (projects/*.jsonl)
```
