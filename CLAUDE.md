# CLAUDE.md — jeg-cc-marketplace

Guidance for agents working in this repo. Keep it concise and high-signal; user-facing docs
live in each plugin's `README.md`. Plugin-specific notes live in `plugins/<name>/CLAUDE.md` —
**read that too** before touching a plugin.

## What this repo is

A **Claude Code plugin marketplace** named `jeg`. It publishes plugins that users install with
`claude plugin install <name>@jeg`. The repo itself is the marketplace source.

```
.claude-plugin/marketplace.json   # the registry: one entry per plugin (name, source, version, description)
README.md                         # marketplace-level user docs
plugins/<name>/                   # one directory per plugin (self-contained)
  .claude-plugin/plugin.json      # plugin manifest (name, version, description)
  commands/*.md                   # slash commands — each .md is agent INSTRUCTIONS, run step by step
  hooks/hooks.json + *.sh         # optional lifecycle hooks
  scripts/*.sh                    # optional helper scripts
  README.md / ROADMAP.md          # user docs
  CLAUDE.md                       # agent notes for THIS plugin
```

Currently one plugin: **cc-cnf-sync** (config + per-project memory sync). See
[plugins/cc-cnf-sync/CLAUDE.md](plugins/cc-cnf-sync/CLAUDE.md).

## How command `.md` files work

A command's `.md` is **not documentation** — it is a script of instructions the agent executes
top to bottom. `bash` code blocks are run by the agent, which carries values (like `$TEMP_DIR`)
forward between blocks. Write them imperatively, portably, and with the expected output the next
step relies on.

## Conventions that apply to every plugin

- **Cross-platform, always.** Everything runs through `bash` (on Windows, Claude Code uses Git
  Bash). `~/.claude` resolves correctly on every OS. **Do not rely on `jq`/`python`/GNU-only
  tools** being installed — prefer POSIX `sh`, `grep`, `sed`, `awk`, `cut`. Beware Git Bash
  quirks (e.g. `sed -n 's/…/p'` over files can abort — prefer `grep | cut`).
- **Versioning (semver).** On every published change bump the version in **both**
  `plugins/<name>/.claude-plugin/plugin.json` **and** the plugin's entry in
  `.claude-plugin/marketplace.json` (`version` + keep `description` identical), plus the
  marketplace `metadata.version`. These must not drift.
- **Git workflow — never commit directly to `main`.** Branch → commit → `merge --no-ff` → push
  → delete branch. Commit messages are conventional (`fix(scope): … (vX.Y.Z)`), and end with:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Commit/push only when the user asks.
- **Push auth on the dev machine.** This Linux box has no default git credential helper (or
  `gh`'s token may be expired), so an HTTPS push can fail with "could not read Username". Push
  with the token in Basic auth:
  ```bash
  B64=$(printf '%s' "x-access-token:$(tr -d ' \t\r\n' < ~/.config/cc-cnf-sync/token)" | base64 | tr -d '\n')
  git -c http.extraHeader="Authorization: Basic $B64" -c credential.helper= push origin main
  ```
  (Once `gh auth login` is fresh, plain `git push` works via gh's credential helper.)
- **Keep docs in sync with behavior.** A change to a command's flow, a hook's algorithm, or the
  auth model must be reflected in that plugin's `README.md`, its command `.md`, and its
  `CLAUDE.md` in the same change.

## Adding a new plugin

1. Create `plugins/<name>/` with `.claude-plugin/plugin.json`, `commands/`, `README.md`, and a
   `CLAUDE.md`.
2. Register it in `.claude-plugin/marketplace.json` (`plugins[]` entry: name, source
   `./plugins/<name>`, description, version, author, category, keywords).
3. Follow the conventions above.
