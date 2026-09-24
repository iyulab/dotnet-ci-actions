#!/usr/bin/env bash
# Packs the repository and then looks at the result from where a package consumer sits: what is in
# each package, and whether the code a README tells readers to paste compiles against the packages
# that README tells them to install. Both are facts about the published artifact that no build of
# the repository itself can see -- a solution compiles its README examples against nothing, and its
# own tests reference implementation packages the reader was never told to add.
#
# Environment (set by action.yml; every variable has a default so the script also runs by hand):
#   CHECK_PROJECT          solution or project to pack; empty = the one dotnet finds in the cwd
#   CHECK_README           README whose marked snippets are compiled (default README.md)
#   CHECK_REQUIRE_XML_DOCS true = every packaged lib/<tfm>/<name>.dll needs lib/<tfm>/<name>.xml
#   CHECK_MIN_SNIPPETS     fewer marked snippets than this fails, so a marker lost in an edit does
#                          not turn the snippet check into a silent pass (default 0)
#
# A snippet is marked by an HTML comment on the line before its ```csharp fence -- invisible on a
# rendered README:
#   <!-- snippet: compile packages="Acme.Core Acme.DependencyInjection" -->
# Every package the marker names must also appear in one of the README's `dotnet add package` lines,
# so what compiles is exactly what the reader was told to install. Packages this repository packs
# are referenced at the version just packed; any other package at the `--version` its install line
# gives, or the latest stable one when the line gives none (which is what the reader gets).
set -euo pipefail

project="${CHECK_PROJECT:-}"
readme="${CHECK_README:-README.md}"
require_xml="${CHECK_REQUIRE_XML_DOCS:-true}"
min_snippets="${CHECK_MIN_SNIPPETS:-0}"

failures=0
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
feed="$work/feed"
# The path dotnet itself reads (nuget.config): native on Windows shells, unchanged elsewhere.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
mkdir -p "$feed"
# A version no registry holds, unique per run, so the global package cache can never serve a
# package packed by an earlier run under the same number.
version="0.0.0-consumer-check.$(date +%s)"

echo "Packing ${project:-the project in $(pwd)} as $version ..."
if ! pack_out="$(dotnet pack ${project:+"$project"} -c Release -o "$feed" -p:Version="$version" --nologo 2>&1)"; then
  printf '%s\n' "$pack_out" | grep -E 'error|Error' | head -20
  echo "FAIL: dotnet pack failed"
  exit 1
fi

shopt -s nullglob
packages=("$feed"/*.nupkg)
if [ "${#packages[@]}" -eq 0 ]; then
  echo "FAIL: dotnet pack produced no package -- nothing to check"
  exit 1
fi

packed_ids=()
tfms=()
for nupkg in "${packages[@]}"; do
  entries="$(zipinfo -1 "$nupkg")"
  nuspec_name="$(printf '%s\n' "$entries" | grep -E '^[^/]+\.nuspec$' | head -1)"
  nuspec="$(unzip -p "$nupkg" "$nuspec_name")"
  id="$(printf '%s\n' "$nuspec" | sed -n 's:.*<id>\(.*\)</id>.*:\1:p' | head -1)"
  packed_ids+=("$id")

  dlls="$(printf '%s\n' "$entries" | grep -E '^lib/[^/]+/[^/]+\.dll$' || true)"
  while IFS= read -r dll; do
    [ -n "$dll" ] || continue
    tfms+=("$(printf '%s\n' "$dll" | cut -d/ -f2)")
    if [ "$require_xml" = "true" ] && ! printf '%s\n' "$entries" | grep -qxF -- "${dll%.dll}.xml"; then
      fail "$id: $dll has no ${dll%.dll}.xml beside it -- the API documentation is not in the package (GenerateDocumentationFile)"
    fi
  done <<< "$dlls"

  readme_entry="$(printf '%s\n' "$nuspec" | sed -n 's:.*<readme>\(.*\)</readme>.*:\1:p' | head -1)"
  if [ -z "$readme_entry" ]; then
    fail "$id: the package declares no readme -- its registry page shows nothing (PackageReadmeFile)"
  elif ! printf '%s\n' "$entries" | grep -qxF -- "$readme_entry"; then
    fail "$id: declares readme '$readme_entry' but the package does not contain it"
  fi

  if ! printf '%s\n' "$nuspec" | grep -qE '<license[ >]|<licenseUrl>'; then
    fail "$id: the package declares no license"
  fi
  echo "checked package $id"
done

# --- README snippets -------------------------------------------------------------------------------

if [ ! -f "$readme" ]; then
  if [ "$min_snippets" -gt 0 ]; then fail "$readme not found, but at least $min_snippets snippet(s) are required"; fi
  [ "$failures" -eq 0 ] && exit 0 || exit 1
fi

# The reader's install lines: "Id" or "Id@version".
installable="$(grep -oE 'dotnet add package [A-Za-z0-9._-]+( +--version +[^ `]+)?' "$readme" \
  | sed -E 's/dotnet add package ([^ ]+)( +--version +([^ ]+))?/\1@\3/' | sed 's/@$//' || true)"

# Split the marked snippets out: snippet-N/Program.cs and snippet-N/packages.
awk -v dir="$work" '
  /<!--[[:space:]]*snippet:[[:space:]]*compile/ {
    n++; pending = 1; line = NR
    pk = $0; sub(/.*packages="/, "", pk); sub(/".*/, "", pk)
    if ($0 !~ /packages="/) pk = ""
    system("mkdir -p \"" dir "/snippet-" n "\"")
    print pk > (dir "/snippet-" n "/packages"); close(dir "/snippet-" n "/packages")
    print line > (dir "/snippet-" n "/line"); close(dir "/snippet-" n "/line")
    next
  }
  pending && /^[[:space:]]*$/ { next }
  pending && /^```csharp[[:space:]]*$/ { pending = 0; inside = 1; next }
  pending { pending = 0; print "unfenced" > (dir "/snippet-" n "/error"); close(dir "/snippet-" n "/error"); next }
  inside && /^```/ { inside = 0; next }
  inside { print >> (dir "/snippet-" n "/Program.cs") }
' "$readme"

snippet_dirs=("$work"/snippet-*)
echo "found ${#snippet_dirs[@]} marked snippet(s) in $readme"
if [ "${#snippet_dirs[@]}" -lt "$min_snippets" ]; then
  fail "$readme has ${#snippet_dirs[@]} marked snippet(s); at least $min_snippets required -- was a <!-- snippet: compile --> marker lost?"
fi

tfm="$(printf '%s\n' "${tfms[@]:-}" | grep . | sort -uV | tail -1 || true)"
# A package with no assembly (a metapackage) names no framework; the SDK's own is what a new
# console project would get.
[ -n "$tfm" ] || tfm="net$(dotnet --version | cut -d. -f1).0"
cat > "$work/nuget.config" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="packed" value="$(native "$feed")" />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
</configuration>
EOF

for dir in "${snippet_dirs[@]}"; do
  line="$(cat "$dir/line")"
  where="$readme:$line"
  if [ -f "$dir/error" ]; then fail "$where: marker is not followed by a \`\`\`csharp fence"; continue; fi
  if [ ! -s "$dir/Program.cs" ]; then fail "$where: marked snippet is empty"; continue; fi
  wanted="$(cat "$dir/packages")"
  if [ -z "$wanted" ]; then fail "$where: marker names no packages (packages=\"...\")"; continue; fi

  refs=""
  ok=true
  for pkg in $wanted; do
    entry="$(printf '%s\n' "$installable" | grep -iE "^${pkg//./\\.}(@|$)" | head -1 || true)"
    if [ -z "$entry" ]; then
      fail "$where: the snippet needs $pkg, but no \`dotnet add package $pkg\` line in $readme tells the reader to install it"
      ok=false; continue
    fi
    if printf '%s\n' "${packed_ids[@]}" | grep -qixF -- "$pkg"; then
      v="$version"
    elif [ "${entry#*@}" != "$entry" ]; then
      v="${entry#*@}"
    else
      v="*"
    fi
    refs="$refs    <PackageReference Include=\"$pkg\" Version=\"$v\" />
"
  done
  $ok || continue

  # Empty Directory.* files stop MSBuild's upward search, so nothing around the temp directory
  # (central package management, shared props) leaks into what a fresh console project sees.
  echo '<Project />' > "$dir/Directory.Build.props"
  echo '<Project />' > "$dir/Directory.Build.targets"
  printf '<Project><PropertyGroup><ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally></PropertyGroup></Project>\n' > "$dir/Directory.Packages.props"
  cat > "$dir/snippet.csproj" <<EOF
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>$tfm</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
$refs  </ItemGroup>
</Project>
EOF
  if build_out="$(dotnet build "$dir/snippet.csproj" --configfile "$work/nuget.config" -c Release --nologo -v q 2>&1)"; then
    echo "ok: $where compiles with: $wanted"
  else
    fail "$where does not compile with the packages its marker names ($wanted):"
    printf '%s\n' "$build_out" | grep -E ' error ' | sed -E 's/ \[[^]]*\]$//; s/^.*Program\.cs/    Program.cs/' | sort -u | head -20
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "$failures problem(s) found."
  exit 1
fi
echo "All packages and marked snippets pass."
