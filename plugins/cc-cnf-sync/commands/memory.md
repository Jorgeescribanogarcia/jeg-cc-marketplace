# /memory

View and manage the per-project memory that cc-cnf-sync keeps synced — **without opening
GitHub**. It reads from your `claude-code-config` backup and can delete notes you no longer
need, propagating the deletion to every machine.

The text after `/memory` (`$ARGUMENTS`) selects the action:

- `/memory`  or  `/memory list`      → list this project's notes (offer to list all projects)
- `/memory view <note>`              → print a note's full contents
- `/memory delete <note>`            → delete a note everywhere (asks first)

Works on **Linux, macOS and Windows** (Git Bash).

---

## Setup (every action)

Operate on the sync **cache clone** — it is already authenticated via the machine's git
credential helper (same as the memory hook), so no token is needed.

```bash
CACHE="${CC_SYNC_CACHE:-$HOME/.claude/cc-cnf-sync/cache/config}"
if [ ! -d "$CACHE/.git" ]; then echo "NO_CACHE"; fi
BR=$(git -C "$CACHE" symbolic-ref --short HEAD 2>/dev/null); [ -n "$BR" ] || BR=main
GIT_TERMINAL_PROMPT=0 git -C "$CACHE" fetch --quiet origin "$BR" && \
  git -C "$CACHE" reset --hard "origin/$BR" --quiet
```

If it printed `NO_CACHE`, the backup hasn't been cloned on this machine yet. Tell the user to
open any project once (so the `SessionStart` hook clones it) or run `/setup`, then **stop**.

Compute THIS project's memory key exactly like the hook (**must stay identical to `norm_key`
in `hooks/sync-memory.sh`**):

```bash
# Input via $nk_arg, NOT $1: Claude Code empties $1/$0/… inside a slash command's bash at
# runtime, so `k=$1` would become `k=`. Keep this identical to norm_key() in sync-memory.sh.
norm_key() {
  k=$nk_arg; case "$k" in *.git) k=${k%.git};; esac
  case "$k" in *@*:*) host=${k#*@}; host=${host%%:*}; path=${k#*:}; k="$host/$path";; esac
  k=$(printf '%s' "$k" | sed -E 's#^[a-zA-Z]+://##; s#^[^@/]*@##'); printf '%s' "$k" | tr 'A-Z' 'a-z'
}
REMOTE=$(git -C "$PWD" remote get-url origin 2>/dev/null)
if [ -n "$REMOTE" ]; then nk_arg=$REMOTE; KEY=$(norm_key); else KEY="local/$(basename "$PWD" | tr 'A-Z' 'a-z')"; fi
SAFE=$(printf '%s' "$KEY" | sed 's/[^a-z0-9._-]/-/g')
DIR="$CACHE/memory/$SAFE"
```

---

## list  (default — no argument, or `list`)

- If `$DIR` has no `*.md`, tell the user this project has no synced memory yet and stop.
- List the real notes in `$DIR` (exclude `MEMORY.md` and `*.conflict.md`), one per line, each
  with the one-line summary from its `description:` frontmatter when present.
- Print `MEMORY.md` (the index) if it exists.
- Flag any `*.conflict.md` (unreconciled conflicts, reconcile with `/memory view` + edit) and any
  `*.md.deleted` tombstones (already-deleted notes).
- Offer: *"Run `/memory list all` to see every project in your backup."* For `list all`, list the
  subfolders of `$CACHE/memory/` with note counts, mapping `safeKey → name` via `memory-manifest.json`.

## view <note>

- Resolve `<note>` against `$DIR` (accept the name with or without the `.md` suffix).
- Print the file's full contents. If it doesn't exist, say so and list the available notes.

## delete <note>

1. Resolve `$DIR/<note>.md`. If it's absent, say so and stop.
2. Show the note (or its first ~15 lines) and **ask the user to confirm** — deletion is permanent
   and removes the note from the backup **and every machine**.
3. On confirmation, in `$CACHE`:
   ```bash
   git -C "$CACHE" rm -q "memory/$SAFE/<note>.md" 2>/dev/null || rm -f "$DIR/<note>.md"
   : > "$DIR/<note>.md.deleted"                       # tombstone → propagates the deletion everywhere
   # drop the note's line from the index if present:
   [ -f "$DIR/MEMORY.md" ] && grep -v "(<note>.md)" "$DIR/MEMORY.md" > "$DIR/MEMORY.md.tmp" && mv "$DIR/MEMORY.md.tmp" "$DIR/MEMORY.md"
   git -C "$CACHE" add -A "memory/$SAFE"
   git -C "$CACHE" -c user.name="cc-cnf-sync" -c user.email="cc-cnf-sync@$(hostname)" \
       commit -q -m "memory: delete <note> via /memory"
   GIT_TERMINAL_PROMPT=0 git -C "$CACHE" push --quiet origin "$BR"
   ```
4. Also remove the **local** copy for THIS project so it's gone immediately. Its local memory dir is
   `~/.claude/projects/<slug>/memory`, where `<slug>` encodes the current absolute path. Find it by
   scanning `~/.claude/projects/*/` for the dir whose session transcript `cwd` equals `$PWD` (or the
   one already containing `<note>.md`), then `rm` `<note>.md` and drop its `MEMORY.md` line. If you
   can't locate it, tell the user the hook will remove the local copy on the next sync.
5. Confirm what was deleted and that the tombstone will clean the other machines on their next sync.

> **Why a tombstone?** Normally cc-cnf-sync does **not** propagate real-note deletions — that's a
> safety net so an accidental `rm` on one machine can't wipe a note everywhere (it just reappears
> from the backup). `/memory delete` is a *deliberate* action, so it drops a `<note>.md.deleted`
> marker that the hook honors on every machine. To bring a deleted note back, remove that tombstone
> file from `memory/<safeKey>/` in the backup.
