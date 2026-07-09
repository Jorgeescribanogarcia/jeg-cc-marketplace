# /backup

Upload your configuration to GitHub

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

Run the following PowerShell to collect all config files into a temp directory:

```powershell
$TEMP_DIR = "$env:TEMP\claude-config-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Path $TEMP_DIR -Force | Out-Null

$SOURCE = "$env:USERPROFILE\.claude"
$FILES_TO_BACKUP = @(
  "settings.json",
  "CLAUDE.md",
  "keybindings.json"
)

foreach ($file in $FILES_TO_BACKUP) {
  $src = Join-Path $SOURCE $file
  $dst = Join-Path $TEMP_DIR $file
  if (Test-Path $src) {
    $dstDir = Split-Path $dst -Parent
    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    Copy-Item $src $dst -Force
  }
}

foreach ($dir in @("commands", "skills", "agents")) {
  $srcDir = Join-Path $SOURCE $dir
  if (Test-Path $srcDir) {
    Copy-Item $srcDir (Join-Path $TEMP_DIR $dir) -Recurse -Force
  }
}

Write-Output $TEMP_DIR
```

**IMPORTANT — Never include these files:**
- `.credentials.json`
- `settings.local.json`
- `history.jsonl`
- `~/.claude.json`
- Any file containing "token", "secret", or "key" in its name
- `plugins\installed_plugins.json` and `plugins\known_marketplaces.json` — these contain
  **absolute, machine-specific paths** (`C:\Users\<you>\.claude\plugins\cache\...`) and a
  local `cache\` that does not exist on other machines. They are intentionally replaced by
  the portable manifest generated in the next step.
- Session transcripts — `projects\<slug>\*.jsonl` (and any other files directly under a project
  dir). These are large and may contain secrets pasted into the chat. Only each project's
  `memory\` subfolder is backed up (STEP 4c), never the raw sessions.

---

### STEP 4b — Generate a portable plugin manifest

Instead of copying the machine-specific plugin JSONs, distill a portable manifest from the
Claude Code CLI. It records only *what* is installed and *which marketplace* it came from —
no absolute paths, no local cache dirs — so `/restore` can rebuild it on any machine/OS.

```powershell
$mp = claude plugin marketplace list --json | ConvertFrom-Json
$pl = claude plugin list --json | ConvertFrom-Json

$marketplaces = foreach ($m in $mp) {
  # 'add' is the source string `claude plugin marketplace add` accepts:
  #   github source -> "owner/repo", git source -> full clone URL.
  if ($m.source -eq 'github' -and $m.repo) { $add = $m.repo }
  elseif ($m.url)  { $add = $m.url }
  elseif ($m.repo) { $add = $m.repo }
  else { $add = $null }
  [PSCustomObject]@{ name = $m.name; source = $m.source; add = $add }
}

$plugins = foreach ($p in $pl) {
  [PSCustomObject]@{ id = $p.id; scope = $p.scope; enabled = $p.enabled }
}

[PSCustomObject]@{
  schema       = 1
  marketplaces = @($marketplaces)
  plugins      = @($plugins)
} | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $TEMP_DIR "plugins.json") -Encoding UTF8

Get-Content (Join-Path $TEMP_DIR "plugins.json") -Raw
```

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
re-attaches the memory automatically — see STEP 4c's key rules; the hook mirrors them exactly.

```powershell
$PROJECTS = Join-Path $SOURCE "projects"
$memProjects = @()

# Normalize a git remote (or folder name) into an OS-independent key.
# MUST stay identical to norm_key() in hooks/attach-memory.sh.
function Get-StableKey {
  param([string]$cwd)
  $key = $null
  if ($cwd -and (Test-Path $cwd)) {
    $remote = (& git -C $cwd remote get-url origin 2>$null)
    if ($LASTEXITCODE -eq 0 -and $remote) {
      $k = $remote.Trim()
      if ($k.EndsWith('.git')) { $k = $k.Substring(0, $k.Length - 4) }
      if ($k -match '^[^/@]+@([^:]+):(.+)$') { $k = "$($Matches[1])/$($Matches[2])" } # git@host:owner/repo
      $k = $k -replace '^[a-zA-Z]+://', '' -replace '^[^@/]*@', ''                    # scheme + user@
      $key = $k.ToLower()
    }
  }
  if (-not $key -and $cwd) { $key = "local/$((Split-Path $cwd -Leaf).ToLower())" }
  return $key
}

if (Test-Path $PROJECTS) {
  foreach ($proj in Get-ChildItem $PROJECTS -Directory) {
    $memDir = Join-Path $proj.FullName "memory"
    if (-not (Test-Path $memDir)) { continue }
    $files = @(Get-ChildItem $memDir -File -Recurse -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { continue }

    # Recover the project's real cwd from ANY session transcript (the slug can't be reversed
    # reliably, and the first .jsonl may be a summary sidecar with no cwd — so scan them all).
    $cwd = $null
    $m = Select-String -Path (Join-Path $proj.FullName '*.jsonl') -Pattern '"cwd":"([^"]*)"' -List |
         Select-Object -First 1
    if ($m) { $cwd = $m.Matches[0].Groups[1].Value -replace '\\\\','\' }

    $key = Get-StableKey $cwd
    if (-not $key) { $key = "slug/$($proj.Name.ToLower())" }   # last resort
    $safe = ($key -replace '[^a-z0-9._-]','-')
    $name = if ($cwd) { Split-Path $cwd -Leaf } else { $proj.Name }

    $dst = Join-Path $TEMP_DIR "memory\$safe"
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Copy-Item (Join-Path $memDir '*') $dst -Recurse -Force

    $memProjects += [PSCustomObject]@{ slug = $proj.Name; key = $key; safeKey = $safe; name = $name; files = $files.Count }
  }
}

[PSCustomObject]@{ schema = 2; projects = @($memProjects) } |
  ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $TEMP_DIR "memory-manifest.json") -Encoding UTF8

Write-Output "Memory: $($memProjects.Count) project(s) collected."
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

Upload the `memory/` tree and `memory-manifest.json` to the repo alongside the other files.

> **Portability:** because memory is keyed by the git remote (not the path), the `SessionStart` hook
> can re-attach it on any machine/OS where the same repo is checked out — regardless of where it lives
> on disk. Projects with no git remote fall back to a folder-name key (works if the folder name matches).

---

### STEP 5 — Add metadata file

Create a file called `backup-meta.json` in the temp directory:

```json
{
  "backup_date": "<ISO timestamp>",
  "claude_version": "<output of: claude --version>",
  "os": "Windows",
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

Excluded for security:
  ⊘ .credentials.json
  ⊘ settings.local.json
  ⊘ history.jsonl
  ⊘ session transcripts (projects/*.jsonl)
```
