#!/usr/bin/env bash
# End-to-end demonstration, against the REAL treehouse binary and the REAL
# fm-claude-trust.sh scope check, of the failure described in the user intent
# and of the fix on this branch. No pool under the user's real ~/.treehouse is
# touched: a temp dir stands in for the machine-wide default root.
set -u
REPO=/Users/reza/.no-mistakes/worktrees/a8b73e1c82e4/01M331NGR5DD2QNR7C6EH2W72P
TMP=/tmp/th-e2e/run
rm -rf "$TMP"; mkdir -p "$TMP"
DEFAULT_ROOT="$TMP/machine-default-treehouse-root"
PRIMARY="$TMP/primary-home"
SECOND="$TMP/secondmate-home"
CC="$TMP/claude-config"
hr() { printf '\n=== %s ===\n' "$1"; }
trust() { CLAUDE_CONFIG_DIR="$CC" bash "$REPO/bin/fm-claude-trust.sh" "$1" "$2" >/dev/null; }

hr "setup: one origin URL, two homes that each cloned it"
git init -q --bare "$TMP/origin.git"
git init -q "$TMP/seed"; cd "$TMP/seed"
git config user.email t@t; git config user.name t
echo hello > README.md; git add -A; git commit -qm init
git branch -M main; git remote add origin "$TMP/origin.git"; git push -q origin main
mkdir -p "$PRIMARY/projects" "$SECOND/projects" "$SECOND/state"
git clone -q "$TMP/origin.git" "$PRIMARY/projects/demo"
git clone -q "$TMP/origin.git" "$SECOND/projects/demo"
printf 'sm-demo\n' > "$SECOND/.fm-secondmate-home"
echo "shared origin URL   : $(git -C "$SECOND/projects/demo" remote get-url origin)"
echo "primary home clone  : $PRIMARY/projects/demo"
echo "secondmate clone    : $SECOND/projects/demo"

hr "the primary home works first, so the shared pool holds ITS pre-warmed slots"
WT_P=$(cd "$PRIMARY/projects/demo" && TREEHOUSE_ROOT="$DEFAULT_ROOT" treehouse get --lease --no-fetch 2>/dev/null)
echo "primary leased      : $WT_P"
echo "bound to clone      : $(git -C "$WT_P" rev-parse --git-common-dir)"
(cd "$PRIMARY/projects/demo" && TREEHOUSE_ROOT="$DEFAULT_ROOT" treehouse return --force "$WT_P" >/dev/null 2>&1)
echo "primary returned it; the slot is now warm and idle in the shared pool"

hr "BEFORE the fix: the secondmate home shares that pool root"
WT_BAD=$(cd "$SECOND/projects/demo" && TREEHOUSE_ROOT="$DEFAULT_ROOT" treehouse get --lease --no-fetch 2>/dev/null)
echo "treehouse handed it : $WT_BAD"
echo "bound to clone      : $(git -C "$WT_BAD" rev-parse --git-common-dir)   <- the PRIMARY's clone"
echo "its own clone is    : $SECOND/projects/demo/.git"
printf 'fm-spawn trust pre-registration: '
if trust "$WT_BAD" "$SECOND/projects/demo" 2>"$TMP/e1"; then echo OK; else echo "REFUSED - the spawn aborts, the secondmate is inert"; sed 's/^/  /' "$TMP/e1"; fi
(cd "$SECOND/projects/demo" && TREEHOUSE_ROOT="$DEFAULT_ROOT" treehouse return --force "$WT_BAD" >/dev/null 2>&1)

hr "AFTER the fix: fm-wake-lib.sh gives this home its own pool root"
. "$REPO/bin/fm-wake-lib.sh" >/dev/null 2>&1
ROOT_SECOND=$(fm_treehouse_root_for_home "$SECOND") || ROOT_SECOND=
ROOT_PRIMARY=$(fm_treehouse_root_for_home "$PRIMARY") || ROOT_PRIMARY=
echo "root for secondmate : ${ROOT_SECOND:-<none>}"
echo "root for primary    : ${ROOT_PRIMARY:-<none - keeps the default pool, unchanged>}"
WT_OK=$(cd "$SECOND/projects/demo" && TREEHOUSE_ROOT="$ROOT_SECOND" treehouse get --lease --no-fetch 2>/dev/null)
echo "treehouse handed it : $WT_OK"
echo "bound to clone      : $(git -C "$WT_OK" rev-parse --git-common-dir)   <- its OWN clone"
printf 'fm-spawn trust pre-registration: '
if trust "$WT_OK" "$SECOND/projects/demo" 2>"$TMP/e2"; then echo "OK - the secondmate can dispatch work into a worktree of its own clone"; else echo REFUSED; sed 's/^/  /' "$TMP/e2"; fi

hr "the return must reach the pool the slot was leased from"
printf 'return using the default root (what re-deriving at teardown would do): '
if out=$( (cd "$SECOND/projects/demo" && TREEHOUSE_ROOT="$DEFAULT_ROOT" treehouse return --force "$WT_OK") 2>&1 ); then echo "returned"; else echo "FAILED"; printf '%s\n' "$out" | sed 's/^/  /'; fi
printf 'return using treehouse_root= as the spawn recorded it: '
if out=$( (cd "$SECOND/projects/demo" && TREEHOUSE_ROOT="$ROOT_SECOND" treehouse return --force "$WT_OK") 2>&1 ); then echo "returned"; else echo "FAILED"; printf '%s\n' "$out" | sed 's/^/  /'; fi

hr "the two pools are separate and the primary's is untouched"
echo "secondmate pool: $(ls -d "$ROOT_SECOND"/.treehouse/*/ 2>/dev/null | tr '\n' ' ')"
echo "default pool   : $(ls -d "$DEFAULT_ROOT"/.treehouse/*/ 2>/dev/null | tr '\n' ' ')"
