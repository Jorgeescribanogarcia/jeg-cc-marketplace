# /uninstall

Cleanly remove cc-cnf-sync from this machine — the plugin and its local files. Works on
**Linux, macOS and Windows** (Git Bash).

> ⚠️ This does **not** touch your backups on GitHub. Your `claude-code-config` repository and
> everything in it stays intact — you can always `/import` later.
>
> It also does **not** sign you out of the GitHub CLI (`gh auth`), since `gh` is shared with the
> rest of your system. Run `gh auth logout` yourself if you also want to remove that.

## Steps to follow

### STEP 1 — Explain what will happen and confirm

Show the user this summary and wait for confirmation before doing anything:

```
🧹 Uninstall cc-cnf-sync

This will remove from THIS machine:
  • The plugin's config folder (~/.config/cc-cnf-sync/ — backup repo URL, 3-way merge bases)
  • The plugin's local backup cache (~/.claude/cc-cnf-sync/)
  • Any leftover githubToken.sh helper in the working folder
  • The cc-cnf-sync plugin itself

Your GitHub backup repo (claude-code-config) is NOT affected.
Your GitHub CLI login (gh) is NOT affected.

Continue? (reply: yes / no)
```

If the user replies anything other than affirmative, stop.

---

### STEP 2 — Remove the plugin's local files

```bash
rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/cc-cnf-sync"
rm -rf "$HOME/.claude/cc-cnf-sync"
rm -f ./githubToken.sh
echo "Removed local config, cache, and any leftover helper."
```

Show:
```
✅ Local cc-cnf-sync files removed.
```

> Note: earlier versions of this plugin installed a `github` MCP and saved a token. If you set up
> such a version, you may still have a `github` MCP entry (`claude mcp list`). This plugin no
> longer uses it — remove it yourself with `claude mcp remove github --scope user` if nothing else
> needs it.

---

### STEP 3 — Uninstall the plugin

```bash
claude plugin uninstall cc-cnf-sync@jeg
```

If that exact id is not found, list plugins with `claude plugin list` and uninstall the matching
`cc-cnf-sync@<marketplace>` entry instead.

---

### STEP 4 — Final summary

```
✅ cc-cnf-sync uninstalled

Removed:
  ✓ Local config folder (~/.config/cc-cnf-sync/)
  ✓ Local backup cache (~/.claude/cc-cnf-sync/)
  ✓ githubToken.sh helper (if present)
  ✓ Plugin cc-cnf-sync

Left untouched:
  • Your GitHub backup: https://github.com/<username>/claude-code-config
  • Your GitHub CLI login (gh auth)

⚠️  Restart Claude Code to finish unloading the plugin.
```
