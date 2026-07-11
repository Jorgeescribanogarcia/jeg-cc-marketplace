# /setup

First-time setup — validates your GitHub token and configures the GitHub MCP for Claude Code.

Works on **Linux, macOS and Windows** (on Windows, Claude Code runs commands through
Git Bash, so the same `bash` script is used everywhere).

## Steps to follow

### STEP 1 — Check if the GitHub MCP already works

Call any **authenticated** GitHub MCP endpoint to test the current connection — for
example `search_repositories` with query `user:@me` (or `get_me` if the server
exposes it).

- **If the call succeeds** (returns data, no auth error): the MCP is already
  configured and working. Show this and **stop**:
  ```
  ✅ GitHub MCP is already configured and working (@<username>).

  You are ready to use:
    /backup  - Upload your config to GitHub
    /restore - Restore your config from GitHub
    /status  - Show status and last backup date
  ```

- **If the call fails** with an authentication error (e.g. "Bad credentials"), or the
  `github` MCP is not installed at all: continue to Step 2. **Do not** treat a merely
  *present* MCP entry as working — it must actually authenticate.

---

### STEP 2 — Run the setup script

Tell the user:
```
Running setup script...
```

Then execute (capture BOTH the output and the exit code):
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-cc-cnf-sync.sh"
```

The script resolves the token from its first argument, then the
`GITHUB_PERSONAL_ACCESS_TOKEN` environment variable, then a token file saved by a
previous run (`~/.config/cc-cnf-sync/token`). It **validates the token against the
GitHub API**, and only then (re)installs the GitHub MCP. Branch on its exit code:

**Exit code 0 — success.** The script already validated the token and installed the
MCP. Read the authenticated `@<username>` from its output and show:
```
✅ Setup complete! GitHub token validated and MCP installed (@<username>).

⚠️  Restart Claude Code so the MCP reconnects with the new token.
    After restarting, run /status to confirm, then /backup.
```
Then **stop** (do not try to call the MCP in this same session — MCP servers only
reconnect on restart, so an in-session call would still use the old connection).

**Exit code 2 — token missing or rejected by GitHub.** The script wrote a
`githubToken.sh` helper to the current folder and printed its full path. Show the
user a clear, friendly message, including a clickable folder link built from that
absolute path:
```
⚠️ You need a valid GitHub token (with the 'repo' scope) to continue.

1. Open the helper folder: [Open folder](file:///<ABSOLUTE_FOLDER_PATH>/)
2. Run `bash githubToken.sh`, paste a valid token, and press Enter.
   (Create the token at https://github.com/settings/tokens with the 'repo' scope.)
3. Come back here and run /setup again.
```
Then **stop**.

**Exit code 1 — install error.** Show:
```
❌ Setup failed while installing the GitHub MCP.

Check that the Claude Code CLI is on PATH and try /setup again.
```

---

### Notes

- The token is never printed in chat: it is entered through `githubToken.sh` (which
  saves it to `~/.config/cc-cnf-sync/token` with `chmod 600`) or passed directly to
  the script.
- To **change** an already-working token, run `githubToken.sh` with the new token
  (or export `GITHUB_PERSONAL_ACCESS_TOKEN`) and run /setup again — the script always
  re-validates and reinstalls the MCP with the current token.
- Cross-platform: on Windows the same script runs under Git Bash, and `~` maps to
  `C:\Users\<you>`, so no OS-specific paths are needed.
- The token configured here is for the **GitHub MCP** (`/backup`, `/restore`, `/status`). The
  **memory-sync hook does not use it** — it authenticates through the machine's git credential helper
  (git-credential-manager / `osxkeychain` / libsecret / `gh`). Setup also records the backup repo URL to
  `~/.config/cc-cnf-sync/repo` so the hook knows where to push without needing a token or an API call.
