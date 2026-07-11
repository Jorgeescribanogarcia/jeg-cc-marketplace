# /uninstall

Cleanly remove cc-cnf-sync from this machine — the plugin, its saved token, and
(optionally) the GitHub MCP. Works on **Linux, macOS and Windows** (Git Bash).

> ⚠️ This does **not** touch your backups on GitHub. Your `claude-code-config`
> repository and everything in it stays intact — you can always `/import` later.

## Steps to follow

### STEP 1 — Explain what will happen and confirm

Show the user this summary and wait for confirmation before doing anything:

```
🧹 Uninstall cc-cnf-sync

This will remove from THIS machine:
  • The saved GitHub token file (~/.config/cc-cnf-sync/token)
  • Any leftover githubToken.sh helper in the working folder
  • The cc-cnf-sync plugin itself

Your GitHub backup repo (claude-code-config) is NOT affected.

Continue? (reply: yes / no)
```

If the user replies anything other than affirmative, stop.

---

### STEP 2 — Remove the saved token and helper

```bash
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/cc-cnf-sync/token"
rmdir "${XDG_CONFIG_HOME:-$HOME/.config}/cc-cnf-sync" 2>/dev/null || true
rm -f ./githubToken.sh
echo "Removed saved token and helper (if any)."
```

Show:
```
✅ Saved GitHub token removed.
```

---

### STEP 3 — Ask about the GitHub MCP (do NOT remove without asking)

The GitHub MCP may be used by other plugins or workflows, so **ask first**:

```
❓ Do you also want to remove the GitHub MCP (`github`) from Claude Code?

   • Choose NO if you use the GitHub MCP for anything else.
   • Choose YES to remove it completely.

Reply: yes / no
```

- **If YES**, run:
  ```bash
  claude mcp remove github --scope user
  ```
  Then show: `✅ GitHub MCP removed.`

- **If NO**, skip it and show: `⏭️  GitHub MCP kept.`

---

### STEP 4 — Uninstall the plugin

```bash
claude plugin uninstall cc-cnf-sync@jeg
```

If that exact id is not found, list plugins with `claude plugin list` and uninstall the
matching `cc-cnf-sync@<marketplace>` entry instead.

---

### STEP 5 — Final summary

```
✅ cc-cnf-sync uninstalled

Removed:
  ✓ Saved GitHub token
  ✓ githubToken.sh helper (if present)
  <✓ GitHub MCP  |  ⏭️ GitHub MCP kept>
  ✓ Plugin cc-cnf-sync

🛡️  Your backups on GitHub are untouched:
    https://github.com/<username>/claude-code-config

⚠️  Restart Claude Code to finish unloading the plugin.
```
