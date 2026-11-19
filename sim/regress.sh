#!/usr/bin/env bash
# regress.sh: run every build x seed in a regression list and summarize.
# Usage: sim/regress.sh [list]   (default: sim/regress.list)
# Each build compiles once; later seeds reuse it. Exits 0 only if every run passes.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST="${1:-$ROOT/sim/regress.list}"
pass=0 fail=0 failed=()

while read -r build top defines seeds plusargs; do
  case "$build" in ''|\#*) continue ;; esac

  args=(-t "$top" -b "$build")
  [ "$defines"  != "-" ] && for d in ${defines//,/ };  do args+=(-d "$d"); done
  [ "$plusargs" != "-" ] && for p in ${plusargs//,/ }; do args+=(-p "$p"); done

  keep=()
  for s in ${seeds//,/ }; do
    if "$ROOT/sim/run.sh" "${args[@]}" -s "$s" "${keep[@]+"${keep[@]}"}"; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1)); failed+=("$build seed=$s")
    fi
    keep=(-k)
  done
done < "$LIST"

echo "----------------------------------------"
echo "Regression: $pass passed, $fail failed"
for f in "${failed[@]+"${failed[@]}"}"; do echo "  FAILED: $f"; done
[ "$fail" -eq 0 ]
