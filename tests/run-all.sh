#!/usr/bin/env bash
# Run every menubar-guard suite: unit assertions + merged scenarios.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
overall=0
for suite in run-tests.sh run-scenarios.sh; do
  echo "================ $suite ================"
  bash "$HERE/$suite" || overall=1
  echo
done
if [ "$overall" -eq 0 ]; then echo "ALL SUITES GREEN"; else echo "SUITE FAILURES PRESENT"; fi
exit "$overall"
