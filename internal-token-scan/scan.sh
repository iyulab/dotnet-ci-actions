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
#   SCAN_ALLOW           newline-separated allowances, each '<rule> <file>': matches of that one rule
#                        in that one file are not failures. <file> is relative to SCAN_PATH and is
#                        compared as written (no wildcards). Lines starting with '#' are comments.
#   SCAN_MIN_FILES       the scan must have read more files than this, or it is not scanning
#                        the repository (a wrong root reads nothing and passes forever)
#   SCAN_MUST_CONTAIN    a file name that must be among the files read, for the same reason
set -euo pipefail

root="${SCAN_PATH:-.}"
# Without trailing slashes, so that every file grep names starts with "$prefix".
while [ "$root" != "/" ] && [ "${root%/}" != "$root" ]; do root="${root%/}"; done
prefix="${root%/}/"
# The three lists default only when unset: an explicitly empty value means "none", so a caller can
# switch a list off (e.g. scan Dockerfiles alone) instead of silently getting the default back.
extensions="${SCAN_EXTENSIONS-cs,md,ts,py,csproj,props,slnx,yml,yaml,json,sh,ps1,toml,sql,graphql,xml,txt}"
include_names="${SCAN_INCLUDE_NAMES-Dockerfile}"
exclude_dirs="${SCAN_EXCLUDE_DIRS-.git,bin,obj,node_modules,dist,.venv,TestResults,coverage,claudedocs}"
extra_patterns="${SCAN_EXTRA_PATTERNS-}"
allow="${SCAN_ALLOW-}"
min_files="${SCAN_MIN_FILES:-20}"
must_contain="${SCAN_MUST_CONTAIN:-README.md}"

# No check in this script feeds a reader that stops at its first match (grep -q) through a pipe:
# under 'pipefail' the writer's broken pipe then makes a match read as a failure, depending on how
# much was still to be written.
if [[ "$(grep --version 2>/dev/null)" != *'GNU grep'* ]]; then
  echo "::error::this scan needs GNU grep (for -P); the grep on PATH is not GNU grep."
  exit 2
fi

# The built-in set is deliberately narrow: only tokens a machine can judge without context.
# A person's name, an internal host, a project code word all need a reader to judge, and a gate
# that cries wolf gets switched off.
# Each has a rule name, which is how a caller's allowance refers to it.
declare -a rules labels patterns
rules+=("ticket-id");        labels+=("internal ticket or backlog id");   patterns+=('\b(HD-\d+|P\d+-[a-z]\b|BD-\d{8}-\d+)')
rules+=("cycle-number");     labels+=("internal cycle number");           patterns+=('\bcycle-\d+\b')
rules+=("working-document"); labels+=("internal working document");       patterns+=('\bclaudedocs\b|\bISSUE-[A-Za-z0-9][A-Za-z0-9-]*\.md\b')
# A drive path with either slash (`D:\lib`, `D:/lib`; a doubled backslash from an escaped string too), except
# the system roots every Windows runner has -- they name no one's workstation. `X:/` followed by another
# slash is a URL scheme, and the lookbehind keeps `Xc:\` inside an identifier out.
rules+=("local-path");       labels+=("absolute local path");             patterns+=('(?<![A-Za-z0-9])[A-Za-z]:(?:\\{1,2}+|/(?!/))(?!Program Files(?: \(x86\))?[\\/]|Windows[\\/])|/home/[a-z]|/Users/[A-Za-z]')

if [ -n "$extra_patterns" ]; then
  extra=0
  while IFS= read -r line; do
    [ -z "${line// /}" ] && continue
    extra=$((extra + 1))
    rules+=("extra-$extra"); labels+=("extra pattern: $line"); patterns+=("$line")
  done <<< "$extra_patterns"
fi

# Allowances: parallel lists, one element per entry.
declare -a allow_rules=() allow_files=() allow_uses=()
while IFS= read -r line; do
  line="${line%$'\r'}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  case "$line" in '' | '#'*) continue ;; esac
  rule="${line%%[[:space:]]*}"
  file="${line#"$rule"}"
  file="${file#"${file%%[![:space:]]*}"}"
  file="${file#./}"
  known=0
  for r in "${rules[@]}"; do [ "$r" = "$rule" ] && known=1; done
  if [ "$known" -ne 1 ]; then
    echo "::error::unknown rule '$rule' in the allowance '$line' -- the rules are: ${rules[*]}."
    exit 2
  fi
  if [ -z "$file" ]; then
    echo "::error::the allowance '$line' names no file -- write '<rule> <file>'."
    exit 2
  fi
  allow_rules+=("$rule"); allow_files+=("$file"); allow_uses+=(0)
done <<< "$allow"

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
# The name is compared as written (not as a pattern) with the end of each listed path.
if ! WANT="/$must_contain" awk 'BEGIN { want = ENVIRON["WANT"]; size = length(want) }
    substr($0, length($0) - size + 1) == want { found = 1 }
    END { exit !found }' <<< "$corpus"; then
  echo "::error::the scan did not read '$must_contain' under '$root' -- it is not covering the repository."
  exit 1
fi
echo "Scanning $corpus_count files under '$root'."

failed=0
hits_file="$(mktemp)"
trap 'rm -f "$hits_file"' EXIT
for i in "${!patterns[@]}"; do
  set +e
  # -Z ends each file name with a NUL, so a name holding ':' or a space is still read whole.
  grep "${grep_args[@]}" -Z -H -n -o -P -- "${patterns[$i]}" "$root" > "$hits_file"
  status=$?
  set -e
  case "$status" in
    0)
      reported=""
      while IFS= read -r -d '' file && IFS= read -r match; do
        allowed=0
        for ((a = 0; a < ${#allow_rules[@]}; a++)); do
          if [ "${allow_rules[$a]}" = "${rules[$i]}" ] && [ "${prefix}${allow_files[$a]}" = "$file" ]; then
            allow_uses[a]=$((allow_uses[a] + 1))
            allowed=1
            break
          fi
        done
        if [ "$allowed" -eq 0 ]; then reported+="$file:$match"$'\n'; fi
      done < "$hits_file"
      if [ -n "$reported" ]; then
        failed=1
        echo "::error::a published file must not carry ${labels[$i]} (rule ${rules[$i]}) -- say what the thing means instead of naming a record only the authors can open:"
        printf '%s' "$reported"
      fi
      ;;
    1) ;;
    *)
      echo "::error::grep exited with status $status while scanning for ${labels[$i]} -- the scan did not complete."
      exit "$status"
      ;;
  esac
done

# Every allowance is shown with what it let through, and one that let nothing through fails: a
# leftover or a mistyped entry would otherwise wait to exempt something nobody reviewed.
for ((a = 0; a < ${#allow_rules[@]}; a++)); do
  if [ "${allow_uses[$a]}" -eq 0 ]; then
    failed=1
    echo "::error::the allowance '${allow_rules[$a]} ${allow_files[$a]}' exempts nothing -- remove it, or correct the file (written relative to 'path', without wildcards)."
  else
    echo "Allowed ${allow_uses[$a]} match(es): ${allow_rules[$a]} ${allow_files[$a]}"
  fi
done

if [ "$failed" -ne 0 ]; then
  exit 1
fi
echo "No published text names something only an insider can look up."
