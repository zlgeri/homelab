#!/usr/bin/env bash
# Black-box tests for laptop/bin/pi-push. The "Pi" is simulated by a local directory,
# so no network, SSH or Raspberry Pi is needed. Requires: bash, rsync, flock, numfmt, script (optional).
#   ./tests/pi-push.test.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
P="$HERE/../laptop/bin/pi-push"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

export HOME="$T/home"; mkdir -p "$HOME"
export XDG_STATE_HOME="$T/state"
SRC="$T/docs"; PI="$T/pi/for-pc"; PTMP="$T/pi/.tmp"
mkdir -p "$SRC" "$PI" "$PTMP"
export PI_SRC="$SRC" PI_DEST="$PI/" PI_TMP="$PTMP" PI_DF_CMD="echo 100000000000"

fail=0
ok()  { echo "OK   $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
run() { out="$("$P" "$@" 2>&1 </dev/null)"; rc=$?; }       # non-interactive

mkdir -p "$SRC/school/math" "$SRC/node_modules/x" "$SRC/.git" "$SRC/.cache" "$SRC/app/bin/Debug" "$SRC/app/obj"
echo a > "$SRC/school/math/notes.txt"
echo b > "$SRC/árvíztűrő tükörfúrógép.txt"
echo c > "$SRC/sp ace.txt"
printf 'n' > "$SRC/$(printf 'new\nline.txt')"
echo x > "$SRC/node_modules/x/i.js"; echo x > "$SRC/.git/HEAD"; echo x > "$SRC/.cache/c"
echo x > "$SRC/app/bin/Debug/app.dll"; echo x > "$SRC/app/obj/cache"
echo x > "$SRC/dl.crdownload"; echo x > "$SRC/a.swp"; echo x > "$SRC/b~"; echo x > "$SRC/f.tmp"

echo "--- 1: first run without a flag"
run
chk "exit 2" '[ $rc = 2 ]'
chk "explains the choice" 'grep -q -- "--from-now" <<<"$out"'
chk "nothing transferred" '[ -z "$(ls -A "$PI")" ]'

echo "--- 2: missing directory / unknown option"
run /no/such/dir;  chk "66" '[ $rc = 66 ]'
run --bogus;       chk "64" '[ $rc = 64 ]'

echo "--- 3: --from-now -> no new files afterwards"
sleep 0.05
run --from-now;    chk "from-now exit 0" '[ $rc = 0 ]'
run;               chk "no new files" '[ $rc = 0 ] && grep -q "no new files" <<<"$out"'
chk "Pi still empty" '[ -z "$(ls -A "$PI")" ]'

echo "--- 4: new files -> dry run, refuse without -y when non-interactive, then -y"
sleep 0.05
mkdir -p "$SRC/school/it"; echo hello > "$SRC/school/it/new essay.txt"
echo more > "$SRC/notes2.md"
run -n;            chk "dry run exit 0 + says so" '[ $rc = 0 ] && grep -q "dry run" <<<"$out" && grep -q "2 file" <<<"$out"'
chk "Pi empty after dry run" '[ -z "$(ls -A "$PI")" ]'
run;               chk "non-interactive without -y -> exit 5" '[ $rc = 5 ]'
chk "Pi empty after exit 5" '[ -z "$(ls -A "$PI")" ]'
run -y;            chk "push exit 0" '[ $rc = 0 ]'
chk "files arrived (spaces, accents)" '[ -f "$PI/school/it/new essay.txt" ] && [ -f "$PI/notes2.md" ]'
chk "temp dir empty" '[ -z "$(ls -A "$PTMP")" ]'
run;               chk "no new files after push" 'grep -q "no new files" <<<"$out"'

echo "--- 5: files deleted on the Pi are not re-sent"
rm -rf "$PI"/*
run;               chk "still no new files" 'grep -q "no new files" <<<"$out"'
chk "Pi stays empty" '[ -z "$(ls -A "$PI")" ]'

echo "--- 6: modification -> only the modified file is sent"
sleep 0.05
echo changed >> "$SRC/notes2.md"
run -y;            chk "1 file sent" '[ $rc = 0 ] && grep -q "^1 file" <<<"$out"'
chk "only the modified file on the Pi" '[ "$(find "$PI" -type f | wc -l)" = 1 ] && [ -f "$PI/notes2.md" ]'
rm -rf "$PI"/*

echo "--- 7: exclusions + special file names, --all"
run --all -y;      chk "--all exit 0" '[ $rc = 0 ]'
chk "notes.txt present" '[ -f "$PI/school/math/notes.txt" ]'
chk "accented name present" '[ -f "$PI/árvíztűrő tükörfúrógép.txt" ]'
chk "name with space present" '[ -f "$PI/sp ace.txt" ]'
chk "name with newline present" '[ -f "$PI/$(printf "new\nline.txt")" ]'
chk "no node_modules" '[ ! -e "$PI/node_modules" ]'
chk "no .git" '[ ! -e "$PI/.git" ]'
chk "no .cache" '[ ! -e "$PI/.cache" ]'
chk "no bin/Debug, obj" '[ ! -e "$PI/app/bin" ] && [ ! -e "$PI/app/obj" ]'
chk "no crdownload/swp/~/tmp" '[ ! -e "$PI/dl.crdownload" ] && [ ! -e "$PI/a.swp" ] && [ ! -e "$PI/b~" ] && [ ! -e "$PI/f.tmp" ]'
rm -rf "$PI"/*

echo "--- 8: free-space guard"
sleep 0.05; echo z > "$SRC/zzz.txt"
PI_DF_CMD="echo 500000000" run -y;  chk "too big -> exit 4 (1G reserve > 500M free)" '[ $rc = 4 ]'
chk "nothing transferred" '[ ! -e "$PI/zzz.txt" ]'
PI_DF_CMD="false" run -y;           chk "df error -> exit 3" '[ $rc = 3 ]'
PI_DF_CMD="echo 100000000000" PI_RESERVE_MB=1 run -y; chk "enough space -> sent" '[ $rc = 0 ] && [ -f "$PI/zzz.txt" ]'
rm -rf "$PI"/*

echo "--- 9: rsync failure -> marker does not move"
sleep 0.05; echo y > "$SRC/yyy.txt"
PI_DEST="/no/such/place/" run -y; chk "failure exit != 0" '[ $rc != 0 ]'
PI_DEST="$PI/" run -y;            chk "same file goes on the next run" '[ $rc = 0 ] && [ -f "$PI/yyy.txt" ]'
rm -rf "$PI"/*

echo "--- 10: lock"
sleep 0.05; echo q > "$SRC/qqq.txt"
# Same key derivation as pi-push (several state dirs exist by now, so don't guess).
KEYDIR="$XDG_STATE_HOME/pi-push/$(printf '%s\n%s' "$SRC" "$PI_DEST" | sha1sum | cut -c1-10)"
( flock -n 9 || exit 1; run -y; echo "$out" > "$T/lockout"; ) 9>"$KEYDIR/lock" 2>/dev/null
chk "lock respected" 'grep -q "already running" "$T/lockout"'
chk "nothing sent while locked" '[ ! -e "$PI/qqq.txt" ]'
run -y; chk "sent after the lock is released" '[ -f "$PI/qqq.txt" ]'
rm -rf "$PI"/*

echo "--- 11: interactive (pty) y/N"
sleep 0.05; echo w > "$SRC/www.txt"
if command -v script >/dev/null; then
  printf 'n\n' | script -qec "$P" /dev/null >/dev/null 2>&1; chk "n -> not sent" '[ ! -e "$PI/www.txt" ]'
  printf 'y\n' | script -qec "$P" /dev/null >/dev/null 2>&1; chk "y -> sent" '[ -f "$PI/www.txt" ]'
else echo "(script not available, skipped)"; fi

echo "--- 12: ctime: renamed/copied file with an old mtime is still caught"
rm -rf "$PI"/*; sleep 0.05
echo old > "$T/old.txt"; touch -d '2020-01-01' "$T/old.txt"
cp -p "$T/old.txt" "$SRC/old-copy.txt"
run -y; chk "old-mtime copy is sent" '[ -f "$PI/old-copy.txt" ]'

echo "--- 13: long file list (SIGPIPE / pipefail)"
rm -rf "$PI"/*; sleep 0.05
mkdir -p "$SRC/big"; for i in $(seq 1 40); do head -c $((i*1000)) /dev/zero > "$SRC/big/f$i.bin"; done
run -n; chk "dry run with 40 files doesn't crash" '[ $rc = 0 ] && grep -q "40 file" <<<"$out" && grep -q "and 25 more" <<<"$out"'

echo
[ $fail = 0 ] && echo "ALL TESTS PASSED" || echo "$fail TEST(S) FAILED"
exit $fail
