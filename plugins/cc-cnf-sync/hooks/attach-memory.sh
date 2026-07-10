#!/bin/sh
# cc-cnf-sync — SessionStart hook.
#
# Auto-attaches a project's persistent memory across machines/OS. Memory in the
# GitHub backup is keyed by a stable identity (normalized git remote, else folder
# name), NOT by the path-specific slug — so the same project re-hydrates its notes
# whether it lives at D:\...\proj on Windows or /home/you/proj on Linux.
#
# Flow (only does work when the current project has NO memory yet):
#   1. Read cwd + transcript_path from the hook's stdin JSON.
#   2. Compute this project's stable key (git remote -> folder name).
#   3. Ensure a local shallow clone of <user>/claude-code-config (auth via
#      $GITHUB_PERSONAL_ACCESS_TOKEN). Refresh once if the key isn't cached yet.
#   4. Copy memory/<safeKey>/ into ~/.claude/projects/<slug>/memory/ and tell Claude.
#
# Fail-open: every error path exits 0 without disturbing the session.

set +e

emit_context() { # $1 = message -> inject into the session as SessionStart context
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$1"
}

# ── read stdin JSON ────────────────────────────────────────────────
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0

json_str() { # $1 = top-level string field name
  printf '%s' "$INPUT" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -n1
}
# JSON-unescape (\\ -> \, \/ -> /) then fold any Windows backslashes to '/' so
# Git Bash tools (dirname, git -C, find, cp) accept the path on every OS.
path_conv() { printf '%s' "$1" | sed 's#\\\\#\\#g; s#\\/#/#g' | tr '\\' '/'; }

TRANSCRIPT=$(path_conv "$(json_str transcript_path)")
CWD=$(path_conv "$(json_str cwd)")
[ -n "$TRANSCRIPT" ] || exit 0

PROJ_DIR=$(dirname "$TRANSCRIPT")
MEM_DIR="$PROJ_DIR/memory"

# ── already has memory? nothing to do (never clobber current notes) ─
if find "$MEM_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | grep -q .; then
  exit 0
fi

# ── throttle: skip if we checked & found nothing in the last 24h ────
MARKER="$PROJ_DIR/.cc-cnf-sync-checked"
if [ -f "$MARKER" ] && [ -z "$(find "$MARKER" -mmin +1440 2>/dev/null)" ]; then
  exit 0
fi

command -v git >/dev/null 2>&1 || exit 0

# ── stable key from git remote (fallback: folder name) ─────────────
# MUST stay identical to norm_key() in commands/backup.md.
norm_key() {
  k=$1
  case "$k" in *.git) k=${k%.git} ;; esac
  case "$k" in *@*:*) host=${k#*@}; host=${host%%:*}; path=${k#*:}; k="$host/$path" ;; esac
  k=$(printf '%s' "$k" | sed -E 's#^[a-zA-Z]+://##; s#^[^@/]*@##')
  printf '%s' "$k" | tr 'A-Z' 'a-z'
}

REMOTE=""
[ -n "$CWD" ] && REMOTE=$(git -C "$CWD" remote get-url origin 2>/dev/null)
if [ -n "$REMOTE" ]; then
  KEY=$(norm_key "$REMOTE")
elif [ -n "$CWD" ]; then
  KEY="local/$(basename "$CWD" | tr 'A-Z' 'a-z')"
else
  : > "$MARKER"; exit 0
fi
SAFE=$(printf '%s' "$KEY" | sed 's/[^a-z0-9._-]/-/g')

# ── ensure a local cache of the backup repo ────────────────────────
ROOT="$HOME/.claude/cc-cnf-sync"
CACHE="$ROOT/cache/config"
TOKEN=${GITHUB_PERSONAL_ACCESS_TOKEN:-}
HDR=""

resolve_repo() { # sets URL + HDR from the token; returns 1 if unavailable
  [ -n "$TOKEN" ] || return 1
  command -v curl >/dev/null 2>&1 || return 1
  LOGIN=$(curl -fsS -H "Authorization: token $TOKEN" -H "User-Agent: cc-cnf-sync" \
           https://api.github.com/user 2>/dev/null \
           | sed -n 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
  [ -n "$LOGIN" ] || return 1
  URL="https://github.com/$LOGIN/claude-code-config.git"
  # GitHub's git-over-HTTPS rejects "Authorization: Bearer <token>" (git then falls
  # back to prompting for a username and the clone/pull fails non-interactively).
  # Use HTTP Basic with the PAT as the password instead — accepted by GitHub and,
  # because it's passed via -c http.extraHeader (never the remote URL), the token is
  # still not written to the cache's .git/config on disk. base64 ships on Linux,
  # macOS and Git Bash for Windows.
  B64=$(printf '%s' "x-access-token:$TOKEN" | base64 2>/dev/null | tr -d '\n')
  [ -n "$B64" ] || return 1
  HDR="Authorization: Basic $B64"
  return 0
}

ensure_cache() {
  if [ -d "$CACHE/.git" ]; then return 0; fi
  resolve_repo || return 1
  mkdir -p "$(dirname "$CACHE")" 2>/dev/null
  git -c http.extraHeader="$HDR" -c credential.helper= \
      clone --depth 1 "$URL" "$CACHE" >/dev/null 2>&1
}

refresh_cache() {
  [ -d "$CACHE/.git" ] || return 1
  [ -n "$HDR" ] || resolve_repo || return 1
  git -C "$CACHE" -c http.extraHeader="$HDR" -c credential.helper= \
      pull --ff-only >/dev/null 2>&1
}

ensure_cache || { : > "$MARKER"; exit 0; }

SRC="$CACHE/memory/$SAFE"
# Key not in the current cache? Pull once in case the backup is newer, then retry.
[ -d "$SRC" ] || refresh_cache

if [ ! -d "$SRC" ]; then
  : > "$MARKER"          # no backup for this project — remember, recheck in 24h
  exit 0
fi

# ── attach ─────────────────────────────────────────────────────────
mkdir -p "$MEM_DIR" 2>/dev/null
cp -R "$SRC"/. "$MEM_DIR"/ 2>/dev/null
: > "$MARKER"

N=$(find "$MEM_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
emit_context "cc-cnf-sync: restored ${N} memory note(s) for this project from your backup (key: ${KEY})."
exit 0
