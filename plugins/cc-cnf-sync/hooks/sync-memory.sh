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

command -v git >/dev/null 2>&1 || { emit_context "cc-cnf-sync: git is not installed; memory not synced. Install git (it also provides the credential helper the sync uses)."; exit 0; }

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

# ── cache clone of the backup repo (auth via the OS git credential helper) ─
# No PAT: git authenticates through whatever credential helper the machine already
# uses for github.com — git-credential-manager on Windows, osxkeychain on macOS,
# libsecret/store/cache on Linux, or gh's helper. GIT_TERMINAL_PROMPT=0 turns a
# missing credential into a fast failure instead of hanging this (headless) hook.
CACHE="${CC_SYNC_CACHE:-$HOME/.claude/cc-cnf-sync/cache/config}"
CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/cc-cnf-sync"
URL=""
resolve_repo() {
  # test seam: a plain (local, no-auth) remote for offline end-to-end testing
  if [ -n "$CC_SYNC_LOCAL_REMOTE" ]; then URL="$CC_SYNC_LOCAL_REMOTE"; return 0; fi
  # 1. explicit backup URL written by /setup (authoritative, path-independent)
  if [ -f "$CFG_DIR/repo" ]; then
    URL=$(tr -d ' \t\r\n' < "$CFG_DIR/repo" 2>/dev/null)
    [ -n "$URL" ] && return 0
  fi
  # 2. gh CLI, if installed and authenticated
  if command -v gh >/dev/null 2>&1; then
    login=$(gh api user --jq .login 2>/dev/null)
    [ -n "$login" ] && { URL="https://github.com/$login/claude-code-config.git"; return 0; }
  fi
  # 3. derive the owner from this project's origin remote — the same GitHub account
  #    that owns the project owns its claude-code-config backup.
  if [ -n "$CWD" ]; then
    r=$(git -C "$CWD" remote get-url origin 2>/dev/null)
    owner=$(printf '%s' "$r" | sed -E 's#\.git$##; s#^[a-zA-Z]+://##; s#^[^@/]*@##; s#^github\.com[:/]##; s#/.*$##')
    [ -n "$owner" ] && { URL="https://github.com/$owner/claude-code-config.git"; return 0; }
  fi
  return 1
}
# Run git non-interactively with the OS credential helper enabled (no injected header).
git_auth() { GIT_TERMINAL_PROMPT=0 git -c credential.interactive=false "$@"; }

ensure_cache() {
  [ -d "$CACHE/.git" ] && return 0            # cache present; fetch/push reuse its origin creds
  resolve_repo || return 1
  mkdir -p "$(dirname "$CACHE")" 2>/dev/null
  git_auth clone "$URL" "$CACHE" >/dev/null 2>&1
}

if ! ensure_cache; then
  : > "$MARKER"
  if [ -z "$URL" ]; then
    emit_context "cc-cnf-sync: memory not synced — could not determine your backup repo. Run /setup, then reopen this project."
  else
    emit_context "cc-cnf-sync: could not reach your backup on GitHub. Make sure git is authenticated for github.com (its credential manager, or 'gh auth login'); memory will retry next session."
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

# Compare two notes ignoring line-ending (CRLF vs LF) differences, so the same note
# stored with CRLF in the backup (e.g. committed on Windows / via the web) and LF
# locally is NOT flagged as a false conflict. Returns 0 (true) only on a real diff.
notes_differ() {
  cmp -s "$1" "$2" && return 1
  [ "$(tr -d '\r' < "$1" 2>/dev/null)" = "$(tr -d '\r' < "$2" 2>/dev/null)" ] && return 1
  return 0
}

# Per-machine record of which .conflict.md files this machine has materialized. It lets
# a later plain `rm` of a resolved conflict be told apart from "this machine never had
# it", so the deletion can be propagated (via tombstones) instead of resurrecting. Kept
# in the local memory dir under a dot-name, so the *.md-only merge never syncs it.
state_has() { [ -f "$STATE" ] && grep -qxF "$1" "$STATE" 2>/dev/null; }
state_add() { state_has "$1" || printf '%s\n' "$1" >> "$STATE" 2>/dev/null; }
state_del() { [ -f "$STATE" ] || return 0; grep -vxF "$1" "$STATE" 2>/dev/null > "$STATE.tmp"; mv "$STATE.tmp" "$STATE" 2>/dev/null; }

# ── file-level union merge of $1 (remote/cache dir) and $2 (local dir) ─
# Ends with BOTH dirs holding the union; conflicts keep both copies.
union_merge() {
  cdir=$1; ldir=$2
  mkdir -p "$cdir" "$ldir" 2>/dev/null
  STATE="$ldir/.cc-cnf-sync-conflicts"
  # remote -> local
  for rf in "$cdir"/*.md; do
    [ -e "$rf" ] || continue
    base=$(basename "$rf")
    case "$base" in *.conflict.md) continue ;; esac
    lf="$ldir/$base"
    if [ "$base" = "MEMORY.md" ]; then continue; fi   # handled separately below
    if [ ! -e "$lf" ]; then
      cp "$rf" "$lf" 2>/dev/null
    elif notes_differ "$rf" "$lf"; then
      cf="${base%.md}.conflict.md"
      rm -f "$cdir/$cf.deleted" 2>/dev/null                  # a fresh divergence overrides a stale tombstone
      cp "$rf" "$ldir/$cf" 2>/dev/null                       # keep remote copy locally
      cp "$rf" "$cdir/$cf" 2>/dev/null                       # and propagate the marker
      cp "$lf" "$cdir/$base" 2>/dev/null                     # local wins as canonical
      state_add "$cf"
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
  # ── conflict-file lifecycle (tombstones propagate a resolved-and-deleted conflict) ──
  # Real notes never propagate deletions (safety); .conflict.md files are ephemeral
  # markers, so a deleted one SHOULD disappear everywhere. A `<name>.conflict.md.deleted`
  # tombstone (empty, kept in the backup) carries that removal to every machine.
  # a) apply incoming tombstones: a conflict resolved on another machine is removed here too
  for tomb in "$cdir"/*.conflict.md.deleted; do
    [ -e "$tomb" ] || continue
    cf=$(basename "${tomb%.deleted}")
    rm -f "$cdir/$cf" "$ldir/$cf" 2>/dev/null
    state_del "$cf"
  done
  # b) reconcile the conflict files the backup still holds
  for cfp in "$cdir"/*.conflict.md; do
    [ -e "$cfp" ] || continue
    b=$(basename "$cfp")
    if [ -e "$cdir/$b.deleted" ]; then rm -f "$cdir/$b" 2>/dev/null; continue; fi
    if [ -e "$ldir/$b" ]; then
      state_add "$b"                              # still present locally
    elif state_has "$b"; then
      : > "$cdir/$b.deleted"                      # this machine had it and you deleted it → tombstone
      rm -f "$cdir/$b" 2>/dev/null                # …and drop it from the backup
      state_del "$b"
    else
      cp "$cfp" "$ldir/$b" 2>/dev/null            # new to this machine → materialize it
      state_add "$b"
    fi
  done
  # c) conflicts freshly created on THIS machine that the backup lacks → push them up
  for lfp in "$ldir"/*.conflict.md; do
    [ -e "$lfp" ] || continue
    b=$(basename "$lfp")
    if [ -e "$cdir/$b.deleted" ]; then rm -f "$ldir/$b" 2>/dev/null; state_del "$b"; continue; fi
    [ -e "$cdir/$b" ] || cp "$lfp" "$cdir/$b" 2>/dev/null
    state_add "$b"
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

  git -C "$CACHE" add -A "memory/$EFF" >/dev/null 2>&1
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
