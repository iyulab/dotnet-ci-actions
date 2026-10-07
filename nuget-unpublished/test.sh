#!/usr/bin/env bash
# Exercises check.sh against a stand-in for nuget.org: a `curl` on PATH that answers from a table of
# package ids. Runs in this repository's CI and from a shell; needs bash and jq.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check="$here/check.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

# The stand-in: answers <index>/<id>/index.json from $work/index/<id> -- a file holding
# "<status> <versions json>". An id without a file answers 404.
mkdir -p "$work/bin" "$work/index"
cat > "$work/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -w|-s) [ "$1" = -w ] && shift; shift ;;
    *) url="$1"; shift ;;
  esac
done
id="$(basename "$(dirname "$url")")"
entry="$FAKE_INDEX/$id"
if [ ! -f "$entry" ]; then printf '404'; exit 0; fi
read -r status body < "$entry"
printf '%s' "$body" > "$out"
printf '%s' "$status"
STUB
chmod +x "$work/bin/curl"

# packs <dir> <file>... : empty files standing in for packed packages.
packs() { local dir="$1"; shift; rm -rf "$dir"; mkdir -p "$dir"; for f in "$@"; do : > "$dir/$f"; done; }

# run <expected exit> <expected any or -> <description>
run() {
  local expected="$1" any="$2" what="$3"
  set +e
  out="$(PATH="$work/bin:$PATH" FAKE_INDEX="$work/index" NU_VERSION="$VERSION" NU_PACKAGES="$work/p" GITHUB_OUTPUT= bash "$check" 2>&1)"
  local status=$?
  set -e
  if [ "$status" -ne "$expected" ] || { [ "$any" != - ] && ! printf '%s\n' "$out" | grep -qx "any=$any"; }; then
    echo "FAIL: $what -- expected exit $expected and any=$any, got exit $status"
    printf '%s\n' "$out" | sed 's/^/    /'
    failures=$((failures + 1))
    return 0
  fi
  echo "ok: $what"
}

VERSION=1.2.0
echo '200 {"versions":["1.1.0","1.2.0"]}' > "$work/index/acme.core"
echo '200 {"versions":["1.1.0"]}' > "$work/index/acme.client"

packs "$work/p" Acme.Core.1.2.0.nupkg Acme.Core.1.2.0.snupkg
run 0 false "every package published -- nothing to release"

packs "$work/p" Acme.Core.1.2.0.nupkg Acme.Client.1.2.0.nupkg
run 0 true "one package of two missing -- a partial release is finished, not reported done"

packs "$work/p" Acme.New.1.2.0.nupkg
run 0 true "a package never published"

echo '503 {}' > "$work/index/acme.core"
packs "$work/p" Acme.Core.1.2.0.nupkg
run 1 - "an index that cannot be asked fails closed"

packs "$work/p"
run 1 - "nothing packed is refused"

echo '200 {"versions":["1.2.0"]}' > "$work/index/acme.core"
packs "$work/p" Acme.Core.1.1.0.nupkg
run 1 - "a package packed at another version is refused"

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed."
  exit 1
fi
echo "All checks passed."
