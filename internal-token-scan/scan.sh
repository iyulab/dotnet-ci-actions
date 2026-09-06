#!/usr/bin/env bash
# Fails when any published text in the tree names something only an insider can look up.
#
# Configured entirely through environment variables so the same script runs as a composite
# Action step and from a developer's shell:
#
#   SCAN_PATH            root to scan (default: .)
#   SCAN_EXTENSIONS      comma-separated file extensions to read
#   SCAN_INCLUDE_NAMES   comma-separated exact file names to read as well (files with no extension)
#   SCAN_EXCLUDE_DIRS    comma-separated directory names pruned at any depth
#   SCAN_EXTRA_PATTERNS  newline-separated extra PCRE patterns, appended to the built-in set
#   SCAN_MIN_FILES       the scan must have read more files than this, or it is not scanning
#                        the repository (a wrong root reads nothing and passes forever)
#   SCAN_MUST_CONTAIN    a file name that must be among the files read, for the same reason
set -euo pipefail

root="${SCAN_PATH:-.}"
# The three lists default only when unset: an explicitly empty value means "none", so a caller can
# switch a list off (e.g. scan Dockerfiles alone) instead of silently getting the default back.
extensions="${SCAN_EXTENSIONS-cs,md,ts,py,csproj,props,slnx,yml,yaml,json,sh,ps1,toml,sql,graphql,xml,txt}"
include_names="${SCAN_INCLUDE_NAMES-Dockerfile}"
exclude_dirs="${SCAN_EXCLUDE_DIRS-.git,bin,obj,node_modules,dist,.venv,TestResults,coverage,claudedocs}"
extra_patterns="${SCAN_EXTRA_PATTERNS-}"
min_files="${SCAN_MIN_FILES:-20}"
must_contain="${SCAN_MUST_CONTAIN:-README.md}"

if ! grep --version 2>/dev/null | grep -q 'GNU grep'; then
  echo "::error::this scan needs GNU grep (for -P); the grep on PATH is not GNU grep."
  exit 2
fi

# The built-in set is deliberately narrow: only tokens a machine can judge without context.
# A person's name, an internal host, a project code word all need a reader to judge, and a gate
# that cries wolf gets switched off.
declare -a labels patterns
labels+=("internal ticket or backlog id");   patterns+=('\b(HD-\d+|P\d+-[a-z]\b|BD-\d{8}-\d+)')
labels+=("internal cycle number");           patterns+=('\bcycle-\d+\b')
labels+=("internal working document");       patterns+=('\bclaudedocs\b|\bISSUE-[A-Za-z0-9][A-Za-z0-9-]*\.md\b')
labels+=("absolute local path");             patterns+=('(?<![A-Za-z0-9])[A-Za-z]:\\|/home/[a-z]|/Users/[A-Za-z]')

if [ -n "$extra_patterns" ]; then
  while IFS= read -r line; do
    [ -z "${line// /}" ] && continue
    labels+=("extra pattern: $line"); patterns+=("$line")
  done <<< "$extra_patterns"
fi

grep_args=(-r -I --binary-files=without-match)
if [ -z "${extensions//[[:space:],]/}" ] && [ -z "${include_names//[[:space:],]/}" ]; then
  echo "::error::nothing to scan -- both 'extensions' and 'include-names' are empty."
  exit 2
fi
IFS=',' read -r -a dirs <<< "$exclude_dirs"
for d in "${dirs[@]}"; do
  d="${d//[[:space:]]/}"
  [ -n "$d" ] && grep_args+=("--exclude-dir=$d")
done
IFS=',' read -r -a exts <<< "$extensions"
for e in "${exts[@]}"; do
  e="${e//[[:space:]]/}"; e="${e#.}"
  [ -n "$e" ] && grep_args+=("--include=*.$e")
done
IFS=',' read -r -a names <<< "$include_names"
for n in "${names[@]}"; do
  n="${n//[[:space:]]/}"
  [ -n "$n" ] && grep_args+=("--include=$n")
done

# Self-check: hold the scan to actually reaching the tree. An empty pattern matches every line, so
# -l with it lists exactly the files the pattern passes below will read.
set +e
corpus="$(grep "${grep_args[@]}" -l -e '' -- "$root")"
set -e
corpus_count=0
[ -n "$corpus" ] && corpus_count="$(printf '%s\n' "$corpus" | wc -l | tr -d ' ')"
if [ "$corpus_count" -le "$min_files" ]; then
  echo "::error::the scan read $corpus_count files under '$root' (needs more than $min_files) -- it is not covering the repository."
  exit 1
fi
if ! printf '%s\n' "$corpus" | grep -q -- "/${must_contain}\$"; then
  echo "::error::the scan did not read '$must_contain' under '$root' -- it is not covering the repository."
  exit 1
fi
echo "Scanning $corpus_count files under '$root'."

failed=0
for i in "${!patterns[@]}"; do
  set +e
  hits="$(grep "${grep_args[@]}" -H -n -o -P -- "${patterns[$i]}" "$root")"
  status=$?
  set -e
  case "$status" in
    0)
      failed=1
      echo "::error::a published file must not carry ${labels[$i]} -- say what the thing means instead of naming a record only the authors can open:"
      printf '%s\n' "$hits"
      ;;
    1) ;;
    *)
      echo "::error::grep exited with status $status while scanning for ${labels[$i]} -- the scan did not complete."
      exit "$status"
      ;;
  esac
done

if [ "$failed" -ne 0 ]; then
  exit 1
fi
echo "No published text names something only an insider can look up."
