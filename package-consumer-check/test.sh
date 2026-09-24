#!/usr/bin/env bash
# Exercises check.sh against the fixtures beside it. Runs in this repository's CI and from a shell;
# needs the .NET SDK, because the check packs and builds for real -- a stub would test nothing.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check="$here/check.sh"
failures=0

# run <expected exit code> <description> <fixture> [VAR=value ...]
# Runs the check inside the fixture with the given environment and leaves the output in $out.
run() {
  local expected="$1" what="$2" fixture="$3"; shift 3
  set +e
  out="$(cd "$here/fixtures/$fixture" && env "$@" bash "$check" 2>&1)"
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

run 0 "a documented package whose marked snippet compiles passes" good CHECK_MIN_SNIPPETS=1 || true
expect "ok: README.md:7 compiles with: Fixture.Widgets" "the marked snippet is built"
expect "found 1 marked snippet(s)" "the unmarked fragment is not collected"

run 1 "a lost marker is caught by the minimum" good CHECK_MIN_SNIPPETS=2 || true
expect "at least 2 required" "the minimum names itself"

run 1 "every defect in the bad fixture is reported" bad || true
expect "has no lib/net10.0/Widgets.xml beside it" "a package without its XML documentation"
expect "the package declares no readme" "a package without a readme"
expect "the package declares no license" "a package without a license"
expect "README.md:7 does not compile" "a snippet that does not compile"
expect "CS0200" "the compiler error is shown"
expect "no \`dotnet add package Microsoft.Extensions.DependencyInjection\` line" "a snippet needing a package the reader was never told to install"
expect "README.md:20: marker is not followed by" "a marker with no fence after it"
expect "6 problem(s) found." "each problem counted once"

run 1 "the XML documentation requirement can be switched off, the rest still holds" bad CHECK_REQUIRE_XML_DOCS=false || true
expect "5 problem(s) found." "one fewer problem"

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed."
  exit 1
fi
echo "All checks passed."
