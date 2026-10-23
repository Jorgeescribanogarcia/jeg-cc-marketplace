# /sessions

Manage a project's accumulated chat **sessions** — list, delete, clean, or rename them — without
leaving Claude Code. Sessions are the raw transcripts at `~/.claude/projects/<slug>/<id>.jsonl`, plus a
`<id>/` folder next to each with its subagent transcripts and tool output; they are **not** part of the
backup (cc-cnf-sync never uploads them), they just pile up and take disk space.

The text after `/sessions` (`$ARGUMENTS`) selects the action:

- `/sessions`  or  `/sessions list`        → list this project's sessions
- `/sessions delete <n>`                    → delete session #n (asks first)
- `/sessions clean [keep <N>]`              → keep the N most recent, delete the rest (default N=5; asks first)
- `/sessions clean older <days>`            → delete sessions with no activity for more than `<days>` days
- `/sessions clean larger <MB>`             → delete sessions bigger than `<MB>` megabytes
- `/sessions clean older <days> larger <MB>` → both at once: a session must match **both** to go
- `/sessions rename <n> <new title>`        → give session #n a custom title
- `/sessions all`                           → list sessions across **every** project (accepts `delete`/`clean` too)

Works on **Linux, macOS and Windows** (Git Bash). `<n>` is the index shown by `list`.

**The active session is never deleted**, by any action: neither this one nor any session written to in
the last 10 minutes (it may be open in another window).

---

## Locate this project's session directory

The current project's session dir is the one under `~/.claude/projects/` whose transcripts were
recorded with `cwd` == the current working directory. **Read `.jsonl` with `grep | cut`, never
`sed -n 's/…/p'`** (that aborts in Git Bash).

```bash
norm_path() { printf '%s' "$1" | tr '\134' '/' | tr 'A-Z' 'a-z' | sed 's#//*#/#g; s#^\([a-z]\):#/\1#'; }
HERE=$(norm_path "$PWD")
PDIR=""
for d in "$HOME/.claude/projects"/*/; do
  cwd=$(grep -oh '"cwd":"[^"]*"' "$d"*.jsonl 2>/dev/null | head -1 | cut -d'"' -f4)
  [ -n "$cwd" ] || continue
  [ "$(norm_path "$cwd")" = "$HERE" ] && { PDIR="$d"; break; }
done
[ -n "$PDIR" ] || echo "NO_PROJECT_DIR"
```

If it prints `NO_PROJECT_DIR`, tell the user no session folder matches this project and stop.

## Shared helpers

Define these in every bash call that lists, deletes or cleans. A session is its `.jsonl` **and** its
`<id>/` folder: sizing or deleting only the `.jsonl` under-reports it (subagent transcripts often weigh
as much as the session) and leaves the folder behind as an orphan.

```bash
CUR="${CLAUDE_SESSION_ID}"                         # this session's id (filled in by Claude Code)
case "$CUR" in *[!0-9a-f-]*) CUR="" ;; esac         # anything but an id → rely on the recency guard alone
sess_kb() { # $1 = .jsonl → size of the whole session in KB
  k=$(du -sk "$1" 2>/dev/null | cut -f1); d="${1%.jsonl}"
  [ -d "$d" ] && k=$(( ${k:-0} + $(du -sk "$d" 2>/dev/null | cut -f1) ))
  echo "${k:-0}"
}
human() { awk -v k="$1" 'BEGIN { if (k >= 1048576) printf "%.1fG", k/1048576; else if (k >= 1024) printf "%.0fM", k/1024; else printf "%dK", k }'; }
protected() { # $1 = .jsonl → true for the active session, or one written in the last 10 minutes
  [ -n "$CUR" ] && [ "$(basename "$1" .jsonl)" = "$CUR" ] && return 0
  [ -n "$(find "$1" -mmin -10 2>/dev/null)" ]
}
rm_session() { # $1 = .jsonl → remove it and its folder; the folder only if the name is a session id
  id=$(basename "$1" .jsonl)
  protected "$1" && { echo "skipped (active): $id"; return 0; }
  rm -f "$1"
  case "$id" in ''|*[!0-9a-f-]*) ;; *) rm -rf "${1%.jsonl}" ;; esac
}
```

## A reusable "list the sessions in a dir" helper

Given a project dir in `$1`, print its sessions newest-first with an index:

```bash
list_dir() {  # $1 = project dir
  i=0
  for s in $(ls -t "$1"*.jsonl 2>/dev/null); do
    i=$((i+1))
    id=$(basename "$s" .jsonl)
    title=$(grep -oh '"aiTitle":"[^"]*"' "$s" 2>/dev/null | tail -1 | cut -d'"' -f4)
    [ -n "$title" ] || title="(untitled)"
    size=$(human "$(sess_kb "$s")")
    msgs=$(grep -c '"type":"user"' "$s" 2>/dev/null)
    date=$(stat -c '%y' "$s" 2>/dev/null | cut -d. -f1)
    mark=""; protected "$s" && mark="  ● active"
    printf '  %2d) %-45.45s  %s · %s · %s msgs · %s%s\n' "$i" "$title" "$date" "$size" "$msgs" "${id%%-*}" "$mark"
  done
  [ "$i" = 0 ] && echo "  (no sessions)"
}
```

---

## list  (default — no argument, or `list`)

Run the locator, then `list_dir "$PDIR"`. Head it with the project name (`basename "$PWD"`) and the
total size (`du -sh "$PDIR"`). Remind the user the index `<n>` is what `delete`/`rename` take.

## delete <n>

1. Resolve `<n>` to the nth file in the SAME newest-first order as `list`:
   `TARGET=$(ls -t "$PDIR"*.jsonl 2>/dev/null | sed -n "${n}p")`.
2. If empty, say "no session #n" and stop. If `protected "$TARGET"`, say it is the active session (or
   was written in the last 10 minutes) and stop.
3. Show the target's title + date + size and **ask the user to confirm**.
4. On yes: `rm_session "$TARGET"`. Confirm how much space was freed. (Sessions aren't backed up, so this
   is purely local and permanent — the safety backup is git history of your *memory*, not transcripts.)

## clean

Parse the arguments after `clean`: `keep <N>`, `older <days>`, `larger <MB>` (whole numbers). With none
of them it is `keep 5`. `keep` doesn't combine with the other two; `older` and `larger` combine, and a
session must then match **both**.

```bash
# $1 = project dir, $2 = keep N (or ""), $3 = older-than days (or ""), $4 = larger-than MB (or "")
clean_candidates() {
  j=0
  for s in $(ls -t "$1"*.jsonl 2>/dev/null); do
    j=$((j+1))
    protected "$s" && continue
    if [ -n "$2" ]; then [ "$j" -gt "$2" ] || continue; fi
    if [ -n "$3" ]; then [ -n "$(find "$s" -mmin +$(( $3 * 1440 )) 2>/dev/null)" ] || continue; fi
    if [ -n "$4" ]; then [ "$(sess_kb "$s")" -gt $(( $4 * 1024 )) ] || continue; fi
    echo "$s"
  done
}
```

"No activity" is the transcript's modification time: a session resumed yesterday counts from yesterday.

1. `CAND=$(clean_candidates "$PDIR" "$keep" "$older" "$larger")`. If it is empty, say nothing matches
   and stop.
2. List each candidate (title, date, size, as in `list_dir`), then the count and the total space it
   frees (sum of `sess_kb`), and **ask to confirm**. Mention that the active session is excluded.
3. On yes: `rm_session` each. Report the count and space freed.

## rename <n> <new title>

Claude Code shows a session's title from the **last** `ai-title` record in its `.jsonl`. To rename,
append a fresh one (it overrides the previous title; a resumed session may later re-title itself):

```bash
TARGET=$(ls -t "$PDIR"*.jsonl 2>/dev/null | sed -n "${n}p")
[ -n "$TARGET" ] || { echo "no session #$n"; exit 0; }
SID=$(basename "$TARGET" .jsonl)
# escape " and \ in the requested title for JSON:
T=$(printf '%s' "$new_title" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '{"type":"ai-title","aiTitle":"%s","sessionId":"%s"}\n' "$T" "$SID" >> "$TARGET"
echo "renamed session #$n to: $new_title"
```

Tell the user the new title shows next time the session list refreshes.

## all

Iterate every project dir and print a header + `list_dir` for each:

```bash
for d in "$HOME/.claude/projects"/*/; do
  ls "$d"*.jsonl >/dev/null 2>&1 || continue
  name=$(grep -oh '"cwd":"[^"]*"' "$d"*.jsonl 2>/dev/null | head -1 | cut -d'"' -f4)
  name=$(printf '%s' "$name" | tr '\134' '/' | sed 's#.*/##'); [ -n "$name" ] || name=$(basename "$d")
  echo "── $name ($(du -sh "$d" 2>/dev/null | cut -f1)) ──"
  list_dir "$d"
done
```

For `/sessions all delete`, make the user pick the project + index explicitly (show the list first, then
confirm each removal). `/sessions all clean older <days>` / `larger <MB>` runs `clean_candidates` over
every project dir: show the candidates grouped by project with the grand total, ask **once**, then
`rm_session` each (`keep <N>` keeps N per project). Total space across all projects:
`du -sh "$HOME/.claude/projects"`.

> Sessions are transcripts only — deleting them never touches your **memory** (`memory/*.md`, which
> *is* synced) or your config. It just reclaims disk space from old conversations. Claude Code also
> deletes sessions inactive for longer than `cleanupPeriodDays` (default 30) on its own; set it in
> `~/.claude/settings.json` — which cc-cnf-sync syncs to your other machines — to keep fewer days.
