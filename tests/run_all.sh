#!/bin/bash
# Every Genesis test, one after another, with a summary at the end.
# Each opens a Godot window for a minute or two. The site test needs the
# internet (OpenStreetMap); skip it with --offline.
HERE="$(cd "$(dirname "$0")" && pwd)"
SUITES="selftest demo landscape ui photomatch set pano weather site geo show tools plans live"
[ "${1:-}" = "--offline" ] && SUITES="${SUITES/ site geo/}"
declare -A RESULT
for s in $SUITES; do
  echo "== $s"
  if timeout 1200 bash "$HERE/run_$s.sh" > "/tmp/gn_$s.log" 2>&1; then
    RESULT[$s]="PASS"
  else
    RESULT[$s]="FAIL"
    grep -E "FAIL|SCRIPT ERROR" "/tmp/gn_$s.log" | head -10
  fi
  echo "   ${RESULT[$s]}"
done
echo
echo "Summary:"
failed=0
for s in $SUITES; do
  printf "  %-12s %s\n" "$s" "${RESULT[$s]}"
  [ "${RESULT[$s]}" = "PASS" ] || failed=1
done
exit $failed
