#!/usr/bin/env bash
# run.sh: compile, elaborate and run one simulation with Vivado xsim.
#
# Usage: sim/run.sh -t <top> [-b <build>] [-d NAME=VAL]... [-s <seed>] [-p NAME=VAL]... [-k]
#   -t  top module                 -b  build name (default: <top>)
#   -d  compile-time define        -s  seed (default: 1)
#   -p  plusarg                    -k  reuse an existing build (skip compile/elaborate)
#
# Output goes to sim/out/<build>/. Prints PASS or FAIL and exits 0 only on PASS.
# A run passes only if its log contains "TEST PASSED" and no Error/Fatal lines:
# xsim exits 0 even after $fatal, so its exit code is never trusted.
# Warnings are failures too: any in xvlog/xelab, and any in the simulation log
# after the test's "RESET:" line (before the first reset edge, FSM state is X and
# unique case warns). A test that prints no "RESET:" line gets no exemption.
# Options containing '=' go through --file/-f option files, because cmd.exe
# splits '=' in .bat arguments on Windows.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOP="" BUILD="" SEED=1 KEEP=0
DEFINES=() PLUSARGS=()

while getopts "t:b:d:s:p:k" opt; do
  case "$opt" in
    t) TOP="$OPTARG" ;;
    b) BUILD="$OPTARG" ;;
    d) DEFINES+=("$OPTARG") ;;
    s) SEED="$OPTARG" ;;
    p) PLUSARGS+=("$OPTARG") ;;
    k) KEEP=1 ;;
    *) sed -n '2,10p' "$0"; exit 2 ;;
  esac
done
[ -n "$TOP" ] || { echo "run.sh: -t <top> is required" >&2; exit 2; }
BUILD="${BUILD:-$TOP}"

# Locate the Vivado tools: $VIVADO_BIN, then PATH, then the default Windows install.
tool() {
  local t="$1" d
  for d in "${VIVADO_BIN:-}" "" /c/AMDDesignTools/2025.2/Vivado/bin; do
    if [ -z "$d" ]; then
      command -v "$t" >/dev/null 2>&1 && { echo "$t"; return; }
      command -v "$t.bat" >/dev/null 2>&1 && { echo "$t.bat"; return; }
    else
      [ -f "$d/$t" ] && { echo "$d/$t"; return; }
      [ -f "$d/$t.bat" ] && { echo "$d/$t.bat"; return; }
    fi
  done
  echo "run.sh: cannot find $t; set VIVADO_BIN" >&2; exit 2
}
XVLOG="$(tool xvlog)" XELAB="$(tool xelab)" XSIM="$(tool xsim)"

OUT="$ROOT/sim/out/$BUILD"
SNAP="snap"
LOG="$OUT/seed_${SEED}.log"
mkdir -p "$OUT"
cd "$OUT" || exit 2

fail() { echo "FAIL  $BUILD seed=$SEED  ($1)"; exit 1; }

# First warning line in a log (or in stdin), empty if none. Covers tool messages
# ("WARNING:") and $warning ("Warning:").
first_warning() { grep -i -m1 '^warning' "$@"; }

if [ "$KEEP" -eq 0 ] || [ ! -d "xsim.dir/$SNAP" ]; then
  rm -rf xsim.dir
  {
    echo "-sv"
    for d in "${DEFINES[@]+"${DEFINES[@]}"}"; do echo "-d $d"; done
    # Sources, relative to this build directory (sim/out/<build> -> repo root).
    grep -v -e '^\s*#' -e '^\s*$' "$ROOT/sim/files.f" | sed 's|^|../../../|'
  } > compile.f

  "$XVLOG" -f compile.f --log xvlog.log >/dev/null 2>&1
  { [ $? -eq 0 ] && ! grep -q '^ERROR' xvlog.log; } || fail "compile: sim/out/$BUILD/xvlog.log"

  "$XELAB" "$TOP" -s "$SNAP" -debug typical --timescale 1ns/1ps --log xelab.log >/dev/null 2>&1
  { [ $? -eq 0 ] && ! grep -q '^ERROR' xelab.log; } || fail "elaborate: sim/out/$BUILD/xelab.log"

  for l in xvlog.log xelab.log; do
    w="$(first_warning "$l")"
    # Remove the snapshot so a later -k run cannot reuse a build that failed here.
    [ -z "$w" ] || { rm -rf xsim.dir; fail "warning in sim/out/$BUILD/$l: $w"; }
  done
fi

{
  echo "-R"
  echo "-sv_seed $SEED"
  for p in "${PLUSARGS[@]+"${PLUSARGS[@]}"}"; do echo "-testplusarg $p"; done
  echo "--log seed_${SEED}.log"
} > "run_${SEED}.f"

"$XSIM" "$SNAP" --file "run_${SEED}.f" >/dev/null 2>&1

[ -f "$LOG" ] || fail "no log"
grep -qE '^(Error|Fatal|ERROR|FATAL)' "$LOG" && fail "errors in sim/out/$BUILD/seed_${SEED}.log"
grep -q 'TEST PASSED' "$LOG" || fail "no TEST PASSED in sim/out/$BUILD/seed_${SEED}.log"
if grep -q '^RESET:' "$LOG"; then
  w="$(sed -n '/^RESET:/,$p' "$LOG" | first_warning)"
else
  w="$(first_warning "$LOG")"
fi
[ -z "$w" ] || fail "warning in sim/out/$BUILD/seed_${SEED}.log: $w"
echo "PASS  $BUILD seed=$SEED"
