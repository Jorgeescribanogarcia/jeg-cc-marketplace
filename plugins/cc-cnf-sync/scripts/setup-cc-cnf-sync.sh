#!/usr/bin/env bash
# setup-cc-cnf-sync.sh
# Cross-platform (Linux / macOS / Windows Git Bash) setup, powered by the GitHub CLI (gh).
# Called automatically by /setup.
#
# Design: this plugin NEVER stores a secret. All authentication is delegated to `gh`, which
# keeps the token in the OS credential store (Windows Credential Manager / macOS Keychain /
# libsecret), falling back to its own 600 file only where no store exists. `gh auth setup-git`
# then makes plain `git push` to github.com work — which is exactly how the memory-sync hook
# authenticates. The only thing this plugin persists is the (non-secret) backup repo URL.
#
# Runs headlessly (no interactive prompt that would hang inside Claude Code). The one
# unavoidably-interactive step — `gh auth login` (browser/device OAuth) — is NOT run here;
# on exit code 2, /setup asks the user to run it themselves, then re-runs this script.
#
# Exit codes (consumed by /setup):
#   0 — gh present + authenticated + git wired + backup repo ensured. Prints "OK:<login>".
#   2 — gh present but NOT authenticated (or token invalid). Prints "UNAUTH".
#   3 — gh NOT installed. Prints "MISSING" + a per-OS install hint.
#   1 — unexpected error (e.g. repo create failed).

set -u

CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/cc-cnf-sync"
REPO_NAME="claude-code-config"
REPO_DESC="Automated backup and restore of Claude Code configuration files (settings, plugins, commands, skills, agents) synced to a private GitHub repository."

echo ""
echo "================================================"
echo "  cc-cnf-sync - Setup (GitHub CLI)"
echo "================================================"
echo ""

# ── STEP 1: is gh installed? ───────────────────────────────────────
echo "STEP 1/4 - Checking for the GitHub CLI (gh)..."
if ! command -v gh >/dev/null 2>&1; then
  os=$(uname -s 2>/dev/null || echo unknown)
  case "$os" in
    Darwin) hint="brew install gh" ;;
    Linux)
      if   command -v pacman >/dev/null 2>&1; then hint="sudo pacman -S github-cli"
      elif command -v apt    >/dev/null 2>&1; then hint="sudo apt install gh"
      elif command -v dnf    >/dev/null 2>&1; then hint="sudo dnf install gh"
      elif command -v zypper >/dev/null 2>&1; then hint="sudo zypper install gh"
      else hint="see https://github.com/cli/cli#installation"
      fi ;;
    *MINGW*|*MSYS*|*CYGWIN*) hint="winget install --id GitHub.cli   (or: scoop install gh)" ;;
    *) hint="see https://github.com/cli/cli#installation" ;;
  esac
  echo "  [MISSING] gh is not installed."
  echo "MISSING"
  echo "INSTALL_HINT: $hint"
  exit 3
fi
echo "  gh found: $(gh --version 2>/dev/null | head -n1)"
echo ""

# ── STEP 2: is gh authenticated for github.com? ────────────────────
echo "STEP 2/4 - Checking GitHub authentication..."
if ! gh auth status --hostname github.com >/dev/null 2>&1; then
  echo "  [UNAUTH] Not authenticated (or the stored token is invalid/expired)."
  echo "UNAUTH"
  exit 2
fi
LOGIN=$(gh api user --jq .login 2>/dev/null)
if [ -z "$LOGIN" ]; then
  echo "  [UNAUTH] Could not read your GitHub account from gh."
  echo "UNAUTH"
  exit 2
fi
echo "  Authenticated as @$LOGIN."
echo ""

# ── STEP 3: wire git to authenticate through gh (idempotent) ───────
# Makes `git push`/`fetch` to github.com use gh's credential — the mechanism the
# SessionStart/SessionEnd memory-sync hook relies on. Safe to run every time.
echo "STEP 3/4 - Configuring git to use gh for github.com..."
gh auth setup-git --hostname github.com >/dev/null 2>&1 || true
echo "  git credential helper wired to gh."
echo ""

# ── STEP 4: ensure the private backup repo exists + record its URL ─
echo "STEP 4/4 - Ensuring your backup repository exists..."
if gh repo view "$LOGIN/$REPO_NAME" >/dev/null 2>&1; then
  echo "  Repository $LOGIN/$REPO_NAME already exists."
else
  if gh repo create "$LOGIN/$REPO_NAME" --private --description "$REPO_DESC" >/dev/null 2>&1; then
    echo "  Created private repository $LOGIN/$REPO_NAME."
  else
    echo "  ERROR: could not create $LOGIN/$REPO_NAME (check that your gh token has the 'repo' scope)."
    exit 1
  fi
fi

# Persist the (non-secret) backup URL so the hook and /export/import/status know where to
# push/pull without an API call. NO token is written — gh owns the credential.
mkdir -p "$CFG_DIR" 2>/dev/null
printf '%s' "https://github.com/$LOGIN/$REPO_NAME.git" > "$CFG_DIR/repo"
echo "  Backup repo URL recorded at $CFG_DIR/repo."
echo ""

echo "================================================"
echo "  Setup complete! Connected as @$LOGIN"
echo "================================================"
echo "OK:$LOGIN"
exit 0
