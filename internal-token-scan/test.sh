#!/usr/bin/env bash
# Exercises scan.sh against the fixtures beside it. Runs in this repository's CI and from a shell.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scan="$here/scan.sh"
failures=0

# run <expected exit code> <description> [VAR=value ...]
# Runs the scan with the given environment, checks the exit code, and leaves the output in $out.
run() {
  local expected="$1" what="$2"; shift 2
  set +e
  out="$(env "$@" bash "$scan" 2>&1)"
  local status=$?
  set -e
  if [ "$status" -ne "$expected" ]; then
    echo "FAIL: $what -- expected exit $expected, got $status"
    printf '%s\n' "$out" | sed 's/^/    /'
    failures=$((failures + 1))
    return 1
  fi
  echo "ok: $what (exit $status)"
}

# expect <needle> <description>: the last run's output must contain the needle.
expect() {
  if ! printf '%s\n' "$out" | grep -qF -- "$1"; then
    echo "FAIL: $2 -- output does not mention: $1"
    printf '%s\n' "$out" | sed 's/^/    /'
    failures=$((failures + 1))
  fi
}

# expect_count <needle> <n> <description>: the needle appears exactly n times.
expect_count() {
  local n
  n="$(printf '%s\n' "$out" | grep -cF -- "$1" || true)"
  if [ "$n" -ne "$2" ]; then
    echo "FAIL: $3 -- expected $2 occurrence(s) of '$1', found $n"
    printf '%s\n' "$out" | sed 's/^/    /'
    failures=$((failures + 1))
  fi
}

# 1. A tree with planted tokens fails, and every built-in pattern is reported.
if run 1 "leaky fixture fails" SCAN_PATH="$here/fixtures/leaky" SCAN_MIN_FILES=1; then
  expect "internal ticket or backlog id" "ticket ids reported"
  expect "internal cycle number" "cycle numbers reported"
  expect "internal working document" "working documents reported"
  expect "absolute local path" "local paths reported"
  expect "README.md:6:" "the planted ticket line is located by line"
  expect "notes.py:1:" "a Python file is read"
  expect_count "README.md:12:" 1 "the drive-letter path is reported once"
fi

# 2. Ordinary published text passes.
run 0 "clean fixture passes" SCAN_PATH="$here/fixtures/clean" SCAN_MIN_FILES=1 || true

# 3. The scan refuses to pass on a tree it did not actually read.
empty="$(mktemp -d)"
run 1 "empty tree is rejected" SCAN_PATH="$empty" || true
expect "it is not covering the repository" "empty tree explained"
rmdir "$empty"

run 1 "missing must-contain file is rejected" \
  SCAN_PATH="$here/fixtures/clean" SCAN_MIN_FILES=1 SCAN_MUST_CONTAIN=CHANGELOG.md || true
expect "did not read 'CHANGELOG.md'" "missing file named"

# 4. Lists switch off when explicitly empty, and both empty is refused. With the extension list
# empty only the named file is read -- and notes.py carries a cycle number, so the run fails for
# that reason and no other.
run 1 "an explicitly empty extension list scans only include-names" \
  SCAN_PATH="$here/fixtures/leaky" SCAN_EXTENSIONS="" SCAN_INCLUDE_NAMES="notes.py" \
  SCAN_MIN_FILES=0 SCAN_MUST_CONTAIN=notes.py || true
expect "Scanning 1 files" "exactly the named file is read"
run 2 "both lists empty is refused" \
  SCAN_PATH="$here/fixtures/leaky" SCAN_EXTENSIONS="" SCAN_INCLUDE_NAMES="" || true

# 5. An extra pattern is honoured and labelled.
run 1 "extra pattern is applied" \
  SCAN_PATH="$here/fixtures/clean" SCAN_MIN_FILES=1 SCAN_EXTRA_PATTERNS='example\.org' || true
expect "extra pattern: example\\.org" "extra pattern labelled"

if [ "$failures" -ne 0 ]; then
  echo "$failures check(s) failed."
  exit 1
fi
echo "All checks passed."
