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
  if ! grep -qF -- "$1" <<< "$out"; then
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
  expect "README.md:13:" "a drive path written with forward slashes is reported"
  expect "README.md:14:" "a forward-slash drive path inside a quoted string is reported"
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

# A listing far larger than a pipe buffer, with the required file near its start: every directory
# holds one, so the first match comes early whatever order the file system lists them in. A check
# that stops reading at the first match must not turn into a failure.
large="$(mktemp -d)"
pad="a-file-name-long-enough-to-make-the-listing-of-this-tree-large"
for d in $(seq 1 40); do
  mkdir "$large/dir-$d"
  echo text > "$large/dir-$d/REQUIRED.md"
  for f in $(seq 1 100); do echo text > "$large/dir-$d/$pad-$f.md"; done
done
for attempt in 1 2 3 4 5; do
  run 0 "a large tree whose required file is listed early passes (attempt $attempt)" \
    SCAN_PATH="$large" SCAN_MUST_CONTAIN=REQUIRED.md || true
done
rm -rf "$large"

# The required name is compared as written: a '.' in it does not stand for any character.
similar="$(mktemp -d)"
echo text > "$similar/abc.md"
run 1 "a file that only resembles must-contain does not count" \
  SCAN_PATH="$similar" SCAN_MIN_FILES=0 SCAN_MUST_CONTAIN=a.c.md || true
expect "did not read 'a.c.md'" "the required name is reported as missing"
run 0 "the exact name counts" SCAN_PATH="$similar" SCAN_MIN_FILES=0 SCAN_MUST_CONTAIN=abc.md || true
rm -rf "$similar"

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

# 6. An allowance exempts one rule in one named file, and nothing else.
tree="$here/fixtures/allowed"
all_allowed='local-path tests/Path Tests.cs
cycle-number tests/Path Tests.cs
local-path tests/data.json'

run 1 "without an allowance the tree fails" SCAN_PATH="$tree" SCAN_MIN_FILES=1 || true
expect "Path Tests.cs:6:" "the path is reported without an allowance"

if run 0 "every token allowed by file and rule passes" \
  SCAN_PATH="$tree" SCAN_MIN_FILES=1 SCAN_ALLOW="$all_allowed"; then
  expect "Allowed 1 match(es): local-path tests/Path Tests.cs" "each use of an allowance is shown"
  expect "Allowed 1 match(es): local-path tests/data.json" "a file that cannot carry a comment is allowed"
fi

if run 1 "an allowance for one rule leaves the file's other tokens reported" \
  SCAN_PATH="$tree" SCAN_MIN_FILES=1 SCAN_ALLOW='local-path tests/Path Tests.cs
local-path tests/data.json'; then
  expect "Path Tests.cs:7:cycle-42" "another rule in an allowed file is still reported"
  expect_count "Path Tests.cs:6:" 0 "the allowed rule is not reported"
fi

# The same string in a file nobody listed still fails -- also one that only shares the listed
# file's name.
copy="$(mktemp -d)"
cp -R "$tree/." "$copy"
mkdir -p "$copy/src/tests"
cp "$copy/tests/data.json" "$copy/src/tests/data.json"
if run 1 "the same string in an unlisted file still fails" \
  SCAN_PATH="$copy" SCAN_MIN_FILES=1 SCAN_ALLOW="$all_allowed"; then
  expect "src/tests/data.json:1:/home/s" "the unlisted file is reported"
  expect_count "$copy/tests/data.json:1:" 0 "the listed file stays allowed"
fi
rm -rf "$copy"

# An allowance that exempts nothing is a leftover or a typo, and a wildcard matches no file name.
run 1 "an allowance that exempts nothing fails" \
  SCAN_PATH="$tree" SCAN_MIN_FILES=1 SCAN_ALLOW="$all_allowed
ticket-id tests/data.json" || true
expect "'ticket-id tests/data.json' exempts nothing" "the unused entry is named"

run 1 "a wildcard is not a pattern" \
  SCAN_PATH="$tree" SCAN_MIN_FILES=1 SCAN_ALLOW='local-path tests/*' || true
expect "'local-path tests/*' exempts nothing" "the wildcard entry is named"
expect "tests/data.json:1:" "nothing is exempted by a wildcard"

run 2 "an unknown rule is refused" \
  SCAN_PATH="$tree" SCAN_MIN_FILES=1 SCAN_ALLOW='paths tests/data.json' || true
expect "unknown rule 'paths'" "the unknown rule is named"
run 2 "an entry without a file is refused" \
  SCAN_PATH="$tree" SCAN_MIN_FILES=1 SCAN_ALLOW='local-path' || true

# The file is named relative to the scanned root, however the root is written; comment and blank
# lines are for the reader.
commented="# the path suite is handed drive paths on purpose

  $all_allowed"
run 0 "a root with a trailing slash, comments and blank lines" \
  SCAN_PATH="$tree/" SCAN_MIN_FILES=1 SCAN_ALLOW="$commented" || true
if (cd "$tree" && SCAN_PATH=. SCAN_MIN_FILES=1 SCAN_ALLOW="$all_allowed" bash "$scan" >/dev/null 2>&1); then
  echo "ok: a root of '.' (exit 0)"
else
  echo "FAIL: a root of '.' -- the allowance did not apply"
  failures=$((failures + 1))
fi
run 0 "an entry may start with ./ and end in a carriage return" \
  SCAN_PATH="$tree" SCAN_MIN_FILES=1 SCAN_ALLOW="local-path ./tests/Path Tests.cs$(printf '\r')
cycle-number tests/Path Tests.cs
local-path tests/data.json" || true

# An extra pattern is allowed by its position among the extra patterns.
run 0 "an extra pattern can be allowed" \
  SCAN_PATH="$here/fixtures/clean" SCAN_MIN_FILES=1 SCAN_EXTRA_PATTERNS='no-such-token-here
example\.org' SCAN_ALLOW='extra-2 README.md' || true

if [ "$failures" -ne 0 ]; then
  echo "$failures check(s) failed."
  exit 1
fi
echo "All checks passed."
