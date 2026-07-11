#!/usr/bin/env bash
# setup-cc-cnf-sync.sh
# Cross-platform (Linux / macOS / Windows Git Bash) setup for the GitHub MCP.
# Called automatically by /setup.
#
# Runs headlessly (no interactive prompt that would hang inside Claude Code):
#   1. Token resolved from $1, then $GITHUB_PERSONAL_ACCESS_TOKEN, then a saved token file.
#   2. Token is validated against the GitHub API (https://api.github.com/user).
#   3. If missing OR rejected by GitHub, a `githubToken.sh` helper is written to the
#      current folder and the script exits with code 2 so /setup can guide the user.
#   4. Only a VALID token gets the GitHub MCP (re)installed.

set -u

TOKEN="${1:-}"
TOKEN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/cc-cnf-sync"
TOKEN_FILE="$TOKEN_DIR/token"

echo ""
echo "================================================"
echo "  cc-cnf-sync - Setup"
echo "================================================"
echo ""

# ── Helper: write the token-entry assistant (keeps the secret out of chat) ──
write_token_helper() {
    local helper
    helper="$(pwd)/githubToken.sh"
    cat > "$helper" <<EOF
#!/usr/bin/env bash
# Paste a GitHub token (scope 'repo') without exposing it in the chat.
echo "================================================"
echo "  GITHUB TOKEN - cc-cnf-sync"
echo "================================================"
echo ""
echo "Create a token with the 'repo' scope at:"
echo "  https://github.com/settings/tokens"
echo ""
printf "Paste your GitHub token: "
read -r T
if [ -z "\$T" ]; then
  echo "ERROR: no token entered."
  exit 1
fi
mkdir -p "$TOKEN_DIR"
printf '%s' "\$T" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE" 2>/dev/null || true
echo ""
echo "Done! Token saved for your user account."
echo "Go back to Claude Code and run /setup again."
EOF
    chmod +x "$helper" 2>/dev/null || true
    echo "$helper"
}

# ── STEP 1: resolve the token (arg → env var → saved file) ─────────
echo "STEP 1/3 - Resolving GitHub token..."
if [ -z "$TOKEN" ] && [ -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
    TOKEN="$GITHUB_PERSONAL_ACCESS_TOKEN"
    echo "  Found GITHUB_PERSONAL_ACCESS_TOKEN in the environment."
fi
if [ -z "$TOKEN" ] && [ -f "$TOKEN_FILE" ]; then
    TOKEN="$(tr -d '\r\n' < "$TOKEN_FILE")"
    echo "  Found a token saved by a previous setup."
fi
echo ""

# ── STEP 2: validate the token before touching anything ───────────
echo "STEP 2/3 - Validating token with GitHub..."
LOGIN=""
if [ -n "$TOKEN" ]; then
    RESP="$(curl -fsS \
        -H "Authorization: token $TOKEN" \
        -H "User-Agent: cc-cnf-sync" \
        -H "Accept: application/vnd.github+json" \
        https://api.github.com/user 2>/dev/null || true)"
    LOGIN="$(printf '%s' "$RESP" | sed -n 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
fi

if [ -z "$LOGIN" ]; then
    HELPER="$(write_token_helper)"
    if [ -z "$TOKEN" ]; then
        echo "  [REQUIRED] No GitHub token found."
    else
        echo "  [INVALID] GitHub rejected the token (bad credentials or missing 'repo' scope)."
    fi
    echo "  A helper was created at:"
    echo "    $HELPER"
    echo "  Run it (bash \"$HELPER\"), paste a VALID token (scope 'repo'), then run /setup again."
    exit 2
fi
echo "  Token validated - authenticated as @$LOGIN."
echo ""

# ── STEP 3: persist token + (re)install the GitHub MCP ────────────
echo "STEP 3/3 - Installing GitHub MCP..."

# Persist so future /setup runs find it without asking again (chmod 600).
mkdir -p "$TOKEN_DIR"
printf '%s' "$TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE" 2>/dev/null || true

# Record the backup repo URL for the memory-sync hook. The hook authenticates via
# the OS git credential helper (NOT this token), so it only needs to know *which*
# repo to push to — this file is its authoritative source (it falls back to the
# project's origin owner if absent).
printf '%s' "https://github.com/$LOGIN/claude-code-config.git" > "$TOKEN_DIR/repo"

# Clean any previous (possibly stale) github MCP, then add fresh.
if claude mcp list 2>&1 | grep -qi "github"; then
    claude mcp remove github --scope user >/dev/null 2>&1 || true
    echo "  Removed previous GitHub MCP."
fi

claude mcp add github npx @modelcontextprotocol/server-github \
    --env "GITHUB_PERSONAL_ACCESS_TOKEN=$TOKEN" --scope user
if [ $? -ne 0 ]; then
    echo "  ERROR: Could not install GitHub MCP."
    exit 1
fi
echo "  GitHub MCP installed successfully."

echo ""
echo "================================================"
echo "  Setup complete! Connected as @$LOGIN"
echo "================================================"
echo ""
echo "IMPORTANT: restart Claude Code so the MCP reconnects with the new token."
echo "Then you can use:"
echo "  /backup  - Upload your config to GitHub"
echo "  /restore - Restore your config from GitHub"
echo "  /status  - Show status and last backup date"
echo ""
exit 0
