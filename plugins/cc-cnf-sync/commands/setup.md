# /setup

First-time setup — authenticates with GitHub through the **GitHub CLI (`gh`)** and prepares
your private backup repository. No personal access token is stored by this plugin: `gh` keeps
the credential in your OS credential store, and wires `git` to use it (which is also how the
memory-sync hook authenticates).

Works on **Linux, macOS and Windows** (on Windows, Claude Code runs commands through Git Bash,
so the same `bash` script is used everywhere).

## Steps to follow

### STEP 1 — Run the setup script

Tell the user:
```
Running setup...
```

Then execute (capture BOTH the output and the exit code):
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-cc-cnf-sync.sh"
```

The script checks that `gh` is installed and authenticated, runs `gh auth setup-git` so plain
`git` pushes to github.com work, and ensures your private `claude-code-config` repo exists. It
stores **no token** — only the backup repo URL at `~/.config/cc-cnf-sync/repo`. Branch on its
exit code:

---

**Exit code 0 — success.** The last output line is `OK:<username>`. Everything is ready and
**no restart is needed** (there is no MCP to reconnect). Show:
```
✅ Setup complete! Authenticated as @<username> via the GitHub CLI.
   Backup repo: https://github.com/<username>/claude-code-config

You are ready to use:
  /export  - Upload your config to GitHub
  /import  - Restore your config from GitHub
  /status  - Show status and last backup date
```

---

**Exit code 2 — `gh` is installed but NOT authenticated** (or the stored token expired). The
user must log in once through the browser. Show them this and **stop** — they run the login
themselves (they can type it in this session with the leading `!`):
```
⚠️ You need to sign in to GitHub once with the GitHub CLI.

1. Run this (it opens your browser; approve there — or paste the device code if headless):

     ! gh auth login --hostname github.com --git-protocol https --web --skip-ssh-key -s repo

2. When gh says you're logged in, run /setup again — it will finish automatically.
```
> The `repo` scope is required so the private backup repo can be created and pushed to.
> On a headless/SSH machine, gh prints a one-time code + URL instead of opening a browser.

---

**Exit code 3 — `gh` is NOT installed.** The script printed an `INSTALL_HINT:` line with the
right command for this OS. Show it and **stop**:
```
⚠️ The GitHub CLI (gh) is not installed. Install it, then run /setup again.

  <the INSTALL_HINT command from the script output>

(More options: https://github.com/cli/cli#installation)
```

---

**Exit code 1 — unexpected error** (e.g. the backup repo could not be created). Show the
script's error output and suggest checking that the gh token has the `repo` scope, then retry:
```
❌ Setup failed. See the message above.

If it mentions the repo, re-run the login with the 'repo' scope:
  ! gh auth login --hostname github.com --git-protocol https --web --skip-ssh-key -s repo
then run /setup again.
```

---

### Notes

- **No token is stored by this plugin.** `gh` owns the credential (OS credential store when
  available). To change accounts, run `gh auth logout` then `gh auth login` and `/setup` again.
- `gh auth setup-git` makes `git push`/`fetch` to github.com authenticate through gh — the same
  mechanism the `SessionStart`/`SessionEnd` memory-sync hook uses, so once `/setup` succeeds the
  hook syncs automatically with nothing extra to configure.
- The only file this plugin writes is `~/.config/cc-cnf-sync/repo` (the non-secret backup URL),
  so `/export`, `/import`, `/status` and the hook all know where to push/pull.
- Cross-platform: on Windows the same script runs under Git Bash, and `~` maps to
  `C:\Users\<you>`, so no OS-specific paths are needed.
