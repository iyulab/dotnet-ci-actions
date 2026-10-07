#!/usr/bin/env bash
# Which of the packed .nupkg files nuget.org does not have yet, at the version given.
#
# Every package is asked, not one: a release that pushed some packages and then failed is finished by
# the next run, which a single sentinel package would report as done. It fails closed -- nuget.org
# answering anything but "here is the list" (200) or "no such package" (404) is not taken to mean
# "not published".
#
# Environment:
#   NU_VERSION    the version to look for (required)
#   NU_PACKAGES   directory holding the packed .nupkg files (required; .snupkg are ignored)
#   NU_INDEX      flat-container base URL (default https://api.nuget.org/v3-flatcontainer)
#   GITHUB_OUTPUT where `any=true|false` is written (optional; printed when unset)
set -euo pipefail

version="${NU_VERSION:?NU_VERSION is required}"
packages="${NU_PACKAGES:?NU_PACKAGES is required}"
index="${NU_INDEX:-https://api.nuget.org/v3-flatcontainer}"
listing="$(mktemp)"
trap 'rm -f "$listing"' EXIT

shopt -s nullglob
nupkgs=("$packages"/*.nupkg)
if [ "${#nupkgs[@]}" -eq 0 ]; then
  echo "::error::No .nupkg in '$packages' -- nothing was packed, so there is nothing to ask about."
  exit 1
fi

missing=0
for nupkg in "${nupkgs[@]}"; do
  file="$(basename "$nupkg" .nupkg)"
  case "$file" in
    *."$version") ;;
    *) echo "::error::$file.nupkg is not at version $version -- packed with a different version than asked about."; exit 1 ;;
  esac
  id="$(printf '%s' "${file%."$version"}" | tr '[:upper:]' '[:lower:]')"
  status="$(curl -s -o "$listing" -w '%{http_code}' "$index/$id/index.json" || true)"
  case "$status" in
    200)
      if jq -e --arg v "$version" '.versions | index($v)' "$listing" > /dev/null; then
        echo "$id $version is published"
      else
        echo "$id $version is not published"; missing=1
      fi ;;
    404) echo "$id has never been published"; missing=1 ;;
    *) echo "::error::nuget.org answered '$status' for $id; cannot tell whether $version is published."; exit 1 ;;
  esac
done

any="$([ "$missing" = 1 ] && echo true || echo false)"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "any=$any" >> "$GITHUB_OUTPUT"
else
  echo "any=$any"
fi
[ "$missing" = 1 ] || echo "::notice::$version is already published; nothing to release. Bump <Version> to publish."
