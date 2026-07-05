# /setup

First-time setup — validates your GitHub token and configures the GitHub MCP for Claude Code.

## Steps to follow

### STEP 1 — Check operating system

Run:
```bash
uname -s 2>/dev/null || echo "Windows"
```

If Windows, continue. If Linux/Mac, adapt paths accordingly (use `~/.claude/` instead of `%USERPROFILE%\.claude\`).

---

### STEP 2 — Check if the GitHub MCP already works

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
  `github` MCP is not installed at all: continue to Step 3. **Do not** treat a merely
  *present* MCP entry as working — it must actually authenticate.

---

### STEP 3 — Run the setup script

Tell the user:
```
Running setup script...
```

Then execute (capture BOTH the output and the exit code):
```bash
powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/setup-cc-cnf-sync.ps1"
```

The script resolves the token from `-Token` or the `GITHUB_PERSONAL_ACCESS_TOKEN`
user environment variable, **validates it against the GitHub API**, and only then
(re)installs the GitHub MCP. Branch on its exit code:

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
`githubToken.bat` helper to the current folder and printed its full path. Show the
user a clear, friendly message in **Spanish**, including a clickable folder link
built from that absolute path:
```
⚠️ Necesitas un token de GitHub válido (con permiso 'repo') para continuar.

1. Abre la carpeta del asistente: [Abrir carpeta](file:///<ABSOLUTE_FOLDER_PATH>/)
2. Ejecuta `githubToken.bat`, pega un token válido y pulsa Enter.
   (Crea el token en https://github.com/settings/tokens con scope 'repo'.)
3. Vuelve aquí y ejecuta /setup de nuevo.
```
Then **stop**.

**Exit code 1 — install error.** Show:
```
❌ Setup failed while installing the GitHub MCP.

Check that Claude Code CLI is on PATH and try /setup again.
```

---

### Notes

- The token is never printed in chat: it is entered through `githubToken.bat` (which
  saves it to your user environment) or passed directly to the script.
- To **change** an already-working token, run `githubToken.bat` with the new token
  (or set `GITHUB_PERSONAL_ACCESS_TOKEN`) and run /setup again — the script always
  re-validates and reinstalls the MCP with the current token.
