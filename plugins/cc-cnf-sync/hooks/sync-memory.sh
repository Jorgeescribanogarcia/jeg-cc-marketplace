#!/bin/sh
# cc-cnf-sync — bidirectional per-project memory sync (SessionStart + SessionEnd).
#
# Two-way syncs this project's memory (~/.claude/projects/<slug>/memory/*.md) with
# the GitHub backup, keyed by a stable identity (normalized git remote, else folder
# name) so it follows the project across machines/OS regardless of on-disk path.
#
# Design goals, in order:
#   1. NEVER lose a note. Divergent edits keep BOTH copies; git history is the net.
#   2. Fail-open: any error exits 0 without disturbing the session.
#
# Algorithm (per project, retried on push races):
#   fetch -> reset --hard to remote truth -> file-level union merge with local
#   -> commit -> push -> copy merged result back to local.
# Union merge rules:
#   - note only on one side          -> copied to the other
#   - same note, identical           -> nothing
#   - same note, diverged            -> local kept as <name>.md, remote kept as
#                                       <name>.conflict.md (on BOTH sides)
#   - MEMORY.md                      -> line-union (dedup) — the right index semantic
#   - deletions                      -> NOT propagated in this version (a note deleted
#                                       on one machine reappears from the other)

set +e

emit_context() { # $1 = message -> inject into the session as context
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$1"
}

# ── read stdin JSON ────────────────────────────────────────────────
INPUT=$(cat 2>/dev/null)
[ -n "$INPUT" ] || exit 0

json_str() { printf '%s' "$INPUT" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -n1; }
path_conv() { printf '%s' "$1" | sed 's#\\\\#\\#g; s#\\/#/#g' | tr '\\' '/'; }

TRANSCRIPT=$(path_conv "$(json_str transcript_path)")
CWD=$(path_conv "$(json_str cwd)")
[ -n "$TRANSCRIPT" ] || exit 0

PROJ_DIR=$(dirname "$TRANSCRIPT")
MEM_DIR="$PROJ_DIR/memory"
MARKER="$PROJ_DIR/.cc-cnf-sync-checked"

command -v git >/dev/null 2>&1 || { emit_context "cc-cnf-sync: git is not installed; memory not synced. Install git and curl."; exit 0; }

# ── stable key (MUST match norm_key() in commands/backup.md) ────────
norm_key() {
  k=$1
  case "$k" in *.git) k=${k%.git} ;; esac
  case "$k" in *@*:*) host=${k#*@}; host=${host%%:*}; path=${k#*:}; k="$host/$path" ;; esac
  k=$(printf '%s' "$k" | sed -E 's#^[a-zA-Z]+://##; s#^[^@/]*@##')
  printf '%s' "$k" | tr 'A-Z' 'a-z'
}

REMOTE=""
[ -n "$CWD" ] && REMOTE=$(git -C "$CWD" remote get-url origin 2>/dev/null)
if [ -n "$REMOTE" ]; then KEY=$(norm_key "$REMOTE")
elif [ -n "$CWD" ]; then KEY="local/$(basename "$CWD" | tr 'A-Z' 'a-z')"
else exit 0
fi
SAFE=$(printf '%s' "$KEY" | sed 's/[^a-z0-9._-]/-/g')

# ── cache clone of the backup repo (Basic auth; token never hits disk) ─
CACHE="${CC_SYNC_CACHE:-$HOME/.claude/cc-cnf-sync/cache/config}"
TOKEN=${GITHUB_PERSONAL_ACCESS_TOKEN:-}
HDR=""; URL=""
resolve_repo() {
  # test seam: a plain (local, no-auth) remote for offline end-to-end testing
  if [ -n "$CC_SYNC_LOCAL_REMOTE" ]; then URL="$CC_SYNC_LOCAL_REMOTE"; HDR=""; return 0; fi
  [ -n "$TOKEN" ] || return 1
  command -v curl >/dev/null 2>&1 || return 1
  LOGIN=$(curl -fsS -H "Authorization: token $TOKEN" -H "User-Agent: cc-cnf-sync" \
           https://api.github.com/user 2>/dev/null \
           | sed -n 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
  [ -n "$LOGIN" ] || return 1
  URL="https://github.com/$LOGIN/claude-code-config.git"
  B64=$(printf '%s' "x-access-token:$TOKEN" | base64 2>/dev/null | tr -d '\n')
  [ -n "$B64" ] || return 1
  HDR="Authorization: Basic $B64"
  return 0
}
git_auth() {
  if [ -n "$HDR" ]; then git -c http.extraHeader="$HDR" -c credential.helper= "$@"
  else git "$@"; fi
}

ensure_cache() {
  if [ -d "$CACHE/.git" ]; then [ -n "$HDR" ] || resolve_repo; return $?; fi
  resolve_repo || return 1
  mkdir -p "$(dirname "$CACHE")" 2>/dev/null
  git_auth clone "$URL" "$CACHE" >/dev/null 2>&1
}

if ! ensure_cache; then
  : > "$MARKER"
  if [ -z "$TOKEN" ]; then
    emit_context "cc-cnf-sync: memory not synced — GITHUB_PERSONAL_ACCESS_TOKEN is not set. Run /setup, then reopen this project."
  else
    emit_context "cc-cnf-sync: could not reach your backup on GitHub (network/curl/token). Memory not synced this time; will retry next session."
  fi
  exit 0
fi

BR=$(git -C "$CACHE" symbolic-ref --short HEAD 2>/dev/null); [ -n "$BR" ] || BR=main
MACHINE=$(hostname 2>/dev/null | sed 's/[^A-Za-z0-9._-]/-/g'); [ -n "$MACHINE" ] || MACHINE=unknown
STAMP=$(date +%Y%m%d-%H%M%S 2>/dev/null); [ -n "$STAMP" ] || STAMP=0

# ── locate this project's folder in the cache, following a rename alias ─
resolve_safe() { # echoes the effective safeKey folder name to use in the cache
  s=$SAFE
  if [ ! -d "$CACHE/memory/$s" ] && [ -f "$CACHE/memory/$s.alias" ]; then
    t=$(head -n1 "$CACHE/memory/$s.alias" 2>/dev/null | tr -d ' \t\r\n')
    case "$t" in ''|*/*|.*) : ;; *) [ -d "$CACHE/memory/$t" ] && s=$t ;; esac
  fi
  printf '%s' "$s"
}

# ── file-level union merge of $1 (remote/cache dir) and $2 (local dir) ─
# Ends with BOTH dirs holding the union; conflicts keep both copies.
union_merge() {
  cdir=$1; ldir=$2
  mkdir -p "$cdir" "$ldir" 2>/dev/null
  # remote -> local
  for rf in "$cdir"/*.md; do
    [ -e "$rf" ] || continue
    base=$(basename "$rf")
    case "$base" in *.conflict.md) continue ;; esac
    lf="$ldir/$base"
    if [ "$base" = "MEMORY.md" ]; then continue; fi   # handled separately below
    if [ ! -e "$lf" ]; then
      cp "$rf" "$lf" 2>/dev/null
    elif ! cmp -s "$rf" "$lf"; then
      cp "$rf" "$ldir/${base%.md}.conflict.md" 2>/dev/null   # keep remote copy locally
      cp "$rf" "$cdir/${base%.md}.conflict.md" 2>/dev/null   # and propagate the marker
      cp "$lf" "$cdir/$base" 2>/dev/null                     # local wins as canonical
    fi
  done
  # local -> remote (files the cache does not have yet)
  for lf in "$ldir"/*.md; do
    [ -e "$lf" ] || continue
    base=$(basename "$lf")
    case "$base" in *.conflict.md) continue ;; esac
    [ "$base" = "MEMORY.md" ] && continue
    [ -e "$cdir/$base" ] || cp "$lf" "$cdir/$base" 2>/dev/null
  done
  # MEMORY.md: union of unique lines (order: remote first, then local-only)
  if [ -e "$cdir/MEMORY.md" ] || [ -e "$ldir/MEMORY.md" ]; then
    cat "$cdir/MEMORY.md" "$ldir/MEMORY.md" 2>/dev/null | awk '!seen[$0]++' > "$cdir/MEMORY.md.tmp" 2>/dev/null
    if [ -s "$cdir/MEMORY.md.tmp" ]; then
      cp "$cdir/MEMORY.md.tmp" "$cdir/MEMORY.md" 2>/dev/null
      cp "$cdir/MEMORY.md.tmp" "$ldir/MEMORY.md" 2>/dev/null
    fi
    rm -f "$cdir/MEMORY.md.tmp" 2>/dev/null
  fi
  # bring any brand-new conflict copies back to local too
  for cf in "$cdir"/*.conflict.md; do
    [ -e "$cf" ] || continue
    b=$(basename "$cf"); [ -e "$ldir/$b" ] || cp "$cf" "$ldir/$b" 2>/dev/null
  done
}

# ── sync loop (retry on push race) ─────────────────────────────────
had_local=0
find "$MEM_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | grep -q . && had_local=1
synced=0
i=1
while [ "$i" -le 3 ]; do
  git_auth -C "$CACHE" fetch --quiet origin "$BR" >/dev/null 2>&1
  git -C "$CACHE" reset --hard "origin/$BR" >/dev/null 2>&1 || git -C "$CACHE" reset --hard >/dev/null 2>&1
  EFF=$(resolve_safe)
  CDIR="$CACHE/memory/$EFF"

  union_merge "$CDIR" "$MEM_DIR"

  git -C "$CACHE" add "memory/$EFF" >/dev/null 2>&1
  if git -C "$CACHE" diff --cached --quiet 2>/dev/null; then
    synced=1; break                       # nothing to push; local already updated from remote
  fi
  git -C "$CACHE" -c user.name="cc-cnf-sync" -c user.email="cc-cnf-sync@$MACHINE" \
      commit -q -m "memory-sync: $EFF from $MACHINE @ $STAMP" >/dev/null 2>&1
  if git_auth -C "$CACHE" push --quiet origin "$BR" >/dev/null 2>&1; then
    synced=1; break
  fi
  i=$((i+1))                              # push rejected → loop: refetch, remerge, retry
done

: > "$MARKER"

if [ "$synced" = 1 ]; then
  N=$(find "$MEM_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  C=$(find "$MEM_DIR" -maxdepth 1 -type f -name '*.conflict.md' 2>/dev/null | wc -l | tr -d ' ')
  if [ "$had_local" = 0 ] && [ "$N" -gt 0 ]; then
    msg="cc-cnf-sync: synced ${N} memory note(s) for this project from your backup (key: ${KEY})."
  else
    msg="cc-cnf-sync: memory synced with your backup (${N} note(s), key: ${KEY})."
  fi
  [ "$C" -gt 0 ] && msg="${msg} ${C} note(s) diverged across machines and were kept as .conflict.md for you to reconcile."
  emit_context "$msg"
else
  emit_context "cc-cnf-sync: memory sync could not complete this session (push contention or network); your local notes are untouched and it will retry next session."
fi
exit 0
