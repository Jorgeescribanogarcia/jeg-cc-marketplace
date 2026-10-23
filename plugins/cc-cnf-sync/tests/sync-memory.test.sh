#!/bin/sh
# End-to-end tests for hooks/sync-memory.sh against a local bare remote: no network, no real config.
#   sh plugins/cc-cnf-sync/tests/sync-memory.test.sh
# Each test builds its own temporary "machine": a backup remote, a project repo, a memory dir and empty
# config homes, then runs the hook the way Claude Code does (JSON on stdin).

HOOK="$(cd "$(dirname "$0")/.." && pwd)/hooks/sync-memory.sh"
FAILED=0
check() { # $1 = label, $2 = shell condition
  if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; FAILED=1; fi
}

setup() {
  T=$(mktemp -d)
  git init -q --bare "$T/remote.git"
  git -C "$T/remote.git" symbolic-ref HEAD refs/heads/main
  git clone -q "$T/remote.git" "$T/seed" 2>/dev/null
  git -C "$T/seed" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  git -C "$T/seed" push -q origin HEAD:main
  mkdir -p "$T/proj" "$T/claude/projects/p/memory" "$T/cfg" "$T/agents" "$T/xdg"
  git -C "$T/proj" init -q
  git -C "$T/proj" remote add origin https://github.com/example/proj.git
  MEM="$T/claude/projects/p/memory"
  KEYDIR="memory/github.com-example-proj"
}

# Extra environment for one run goes before the call: CC_SYNC_TEST_AFTER_MERGE=... run_sync
run_sync() {
  printf '{"hook_event_name":"SessionStart","transcript_path":"%s","cwd":"%s"}' "$T/claude/projects/p/s.jsonl" "$T/proj" |
    CC_SYNC_LOCAL_REMOTE="$T/remote.git" CC_SYNC_CACHE="$T/cache" CC_SYNC_CONFIG_HOME="$T/cfg" \
    CC_SYNC_AGENTS_HOME="$T/agents" CC_SYNC_VSCODE_HOME="$T/novscode" XDG_CONFIG_HOME="$T/xdg" sh "$HOOK"
}

on_remote() { # $1 = path in the backup -> its content on the remote's main
  git --git-dir="$T/remote.git" show "main:$1" 2>/dev/null
}

# 1. A sync whose merge never reached the backup must not record that merge as agreed.
# Two hooks share one cache clone; a concurrent one resetting it wipes this sync's merge before the
# push. The next sync then saw "local == base, backup differs" and pulled the stale backup over the
# newer local note. The seam reproduces that reset deterministically.
setup
printf 'v1\n' > "$MEM/a.md"
printf -- '- [A](a.md) — note a v1\n' > "$MEM/MEMORY.md"
run_sync >/dev/null
check "first sync puts the note in the backup" '[ "$(on_remote $KEYDIR/a.md)" = "v1" ]'
printf 'v2\n' > "$MEM/a.md"
printf -- '- [A](a.md) — note a v2\n' > "$MEM/MEMORY.md"
CC_SYNC_TEST_AFTER_MERGE='git -C "$CACHE" reset -q --hard "origin/$BR"' run_sync >/dev/null
check "the wiped sync left the backup at v1 (race reproduced)" '[ "$(on_remote $KEYDIR/a.md)" = "v1" ]'
run_sync >/dev/null
check "the next sync keeps the newer local note" '[ "$(cat "$MEM/a.md")" = "v2" ]'
check "the next sync pushes the newer note" '[ "$(on_remote $KEYDIR/a.md)" = "v2" ]'
check "the next sync keeps the newer index line" 'grep -q "note a v2" "$MEM/MEMORY.md"'
check "no conflict copy for an edit made on one side only" '[ ! -e "$MEM/a.conflict.md" ]'

# 2. The same rule for global config: a lost push must not let the stale backup overwrite CLAUDE.md.
setup
printf 'cfg v1\n' > "$T/cfg/CLAUDE.md"
printf 'n\n' > "$MEM/a.md"
run_sync >/dev/null
printf 'cfg v2\n' > "$T/cfg/CLAUDE.md"
CC_SYNC_TEST_AFTER_MERGE='git -C "$CACHE" reset -q --hard "origin/$BR"' run_sync >/dev/null
run_sync >/dev/null
check "a lost config push does not revert CLAUDE.md" '[ "$(cat "$T/cfg/CLAUDE.md")" = "cfg v2" ]'
check "the config reaches the backup on the next sync" '[ "$(on_remote CLAUDE.md)" = "cfg v2" ]'

# 3. Only one sync at a time: while another holds the lock, this one waits, then gives up untouched.
setup
printf 'v1\n' > "$MEM/a.md"
mkdir "$T/cache.lock"
out=$(CC_SYNC_LOCK_WAIT=2 run_sync)
check "a held lock stops the sync" '[ -z "$(on_remote $KEYDIR/a.md)" ]'
check "the session is told why" 'printf "%s" "$out" | grep -q "another sync"'
rmdir "$T/cache.lock"
run_sync >/dev/null
check "once released, the sync runs" '[ "$(on_remote $KEYDIR/a.md)" = "v1" ]'
check "the lock is released after a sync" '[ ! -d "$T/cache.lock" ]'

# 4. A lock left by a killed sync (the hook has a timeout) is broken once it is stale.
setup
printf 'v1\n' > "$MEM/a.md"
mkdir "$T/cache.lock"
touch -d '20 minutes ago' "$T/cache.lock"
CC_SYNC_LOCK_WAIT=2 run_sync >/dev/null
check "a stale lock is broken" '[ "$(on_remote $KEYDIR/a.md)" = "v1" ]'

# 5. A lock whose owner process is gone is broken at once, however young: the app kills the SessionEnd
# sync on exit, the KILL skips the trap that removes the lock, and the next session used to wait it out.
setup
printf 'v1\n' > "$MEM/a.md"
mkdir "$T/cache.lock"
sh -c 'echo $$' > "$T/cache.lock/owner"        # a PID that has already exited
out=$(CC_SYNC_LOCK_WAIT=2 run_sync)
check "a lock left by a dead process is broken" '[ "$(on_remote $KEYDIR/a.md)" = "v1" ]'
check "…without telling the session another sync is running" '! printf "%s" "$out" | grep -q "another sync"'
setup
printf 'v1\n' > "$MEM/a.md"
mkdir "$T/cache.lock"
sleep 30 & live=$!
echo "$live" > "$T/cache.lock/owner"
CC_SYNC_LOCK_WAIT=2 run_sync >/dev/null
check "a lock whose owner is alive is respected" '[ -z "$(on_remote $KEYDIR/a.md)" ]'
kill "$live" 2>/dev/null

# 6. Config trees are compared in bulk; the per-file results must be what the file-by-file code gave.
setup
mkdir -p "$T/cfg/skills/s" "$T/agents/skills/k"
printf 'same\n' > "$T/cfg/skills/s/same.md"
printf 'crlf\r\nline\r\n' > "$T/cfg/skills/s/crlf.md"
printf 'name with spaces\n' > "$T/cfg/skills/s/has space.md"
printf 'agent skill\n' > "$T/agents/skills/k/SKILL.md"
printf 'n\n' > "$MEM/a.md"
run_sync >/dev/null
check "a tree new to the backup is not mistaken for the backup's copy" '[ -n "$(on_remote skills/s/same.md)" ] && [ "$(cat "$T/cfg/skills/s/same.md")" = "same" ]'
check "tree files reach the backup" '[ "$(on_remote "skills/s/has space.md")" = "name with spaces" ] && [ -n "$(on_remote agents-skills/k/SKILL.md)" ]'
norm() { tr -d '\r' < "$1" | git hash-object --stdin; }
check "base of a CRLF file is its CR-stripped hash" 'grep -qxF "$(norm "$T/cfg/skills/s/crlf.md") skills/s/crlf.md" "$T/xdg/cc-cnf-sync/config-base"'
check "base of a plain file is its hash" 'grep -qxF "$(norm "$T/cfg/skills/s/same.md") skills/s/same.md" "$T/xdg/cc-cnf-sync/config-base"'
check "base of a file with spaces in its name" 'grep -qxF "$(norm "$T/cfg/skills/s/has space.md") skills/s/has space.md" "$T/xdg/cc-cnf-sync/config-base"'
printf 'edited here\n' > "$T/cfg/skills/s/same.md"
git clone -q "$T/remote.git" "$T/other" && printf 'edited there\n' > "$T/other/agents-skills/k/SKILL.md" &&
  git -C "$T/other" -c user.name=t -c user.email=t@t commit -qam other && git -C "$T/other" push -q origin HEAD:main
run_sync >/dev/null
check "a one-sided local edit in a tree is pushed" '[ "$(on_remote skills/s/same.md)" = "edited here" ]'
check "a one-sided backup edit in a tree is pulled" '[ "$(cat "$T/agents/skills/k/SKILL.md")" = "edited there" ]'
check "the cache checks text out as LF even with core.autocrlf=true" 'rm -f "$T/cache/agents-skills/k/SKILL.md" && git -c core.autocrlf=true -C "$T/cache" checkout -q -- agents-skills/k/SKILL.md && ! grep -qU "$(printf "\r")" "$T/cache/agents-skills/k/SKILL.md"'
check "neither leaves a conflict copy" '[ -z "$(find "$T/cfg" "$T/agents" -name "*.cc-conflict")" ]'
printf 'mine\n' > "$T/cfg/skills/s/same.md"
git -C "$T/other" pull -q && printf 'theirs\n' > "$T/other/skills/s/same.md" &&
  git -C "$T/other" -c user.name=t -c user.email=t@t commit -qam both && git -C "$T/other" push -q origin HEAD:main
run_sync >/dev/null
check "an edit on both sides keeps both" '[ "$(cat "$T/cfg/skills/s/same.md")" = "mine" ] && [ "$(cat "$T/cfg/skills/s/same.md.cc-conflict")" = "theirs" ]'

# 7. Speed: a steady-state sync over many unchanged files must not cost a process per file.
setup
for s in $(seq 1 40); do mkdir -p "$T/cfg/skills/s$s"; for f in $(seq 1 15); do printf '%s %s\n' "$s" "$f" > "$T/cfg/skills/s$s/f$f.md"; done; done
printf 'n\n' > "$MEM/a.md"
run_sync >/dev/null
t0=$(date +%s); run_sync >/dev/null; t1=$(date +%s)
echo "     steady-state sync over 600 files: $((t1 - t0)) s"
check "a steady-state sync over 600 files takes under 15 s" '[ $((t1 - t0)) -lt 15 ]'

[ "$FAILED" = 0 ] && echo "all tests passed" || { echo "some tests FAILED"; exit 1; }
