# dotnet-ci-actions

Reusable GitHub composite Actions for .NET CI pipelines.

## Actions

### `vulnerability-scan`

Fails the job if `dotnet list package --vulnerable` reports any vulnerable NuGet
package, direct or transitive. `dotnet list package --vulnerable` alone does not
fail the build on its own — it only prints a report — so this action greps that
report and turns a hit into a non-zero exit.

```yaml
- name: Restore dependencies
  run: dotnet restore

- name: Vulnerability scan
  uses: iyulab/dotnet-ci-actions/vulnerability-scan@<commit-sha>  # pin to a commit, not @main
```

With an explicit solution/project file:

```yaml
- name: Vulnerability scan
  uses: iyulab/dotnet-ci-actions/vulnerability-scan@<commit-sha>  # pin to a commit, not @main
  with:
    project: MySolution.slnx
```

**Requires**: dependencies already restored (`dotnet restore` run earlier in the
job) and `dotnet` on `PATH` (e.g. via `actions/setup-dotnet`).

**Pin to a commit SHA**, not `@main` — a branch ref is mutable, so referencing it
lets this repo change what a consumer's CI runs without that consumer reviewing
or approving the change. Update the pin when you intentionally want a newer
version of the action.

| Input | Required | Default | Description |
|---|---|---|---|
| `project` | no | `''` | Path to a solution or project file. Left empty, `dotnet` discovers the single solution/project in the current directory. |

### `internal-token-scan`

Fails the job if any published text in the checked-out tree names something
only an insider can look up. A published repository is read by people outside
the organisation that develops it, and text written for an internal reader does
not become internal again by sitting in a comment: a fix is written while its
ticket is on screen, the ticket's name goes into the comment explaining the fix,
and every review that reads the change for correctness slides straight past it.

The built-in patterns are deliberately narrow -- only tokens a machine can judge
without context:

| What | Pattern |
|---|---|
| internal ticket or backlog id | `\b(HD-\d+\|P\d+-[a-z]\b\|BD-\d{8}-\d+)` |
| internal cycle number | `\bcycle-\d+\b` |
| internal working document | `\bclaudedocs\b\|\bISSUE-[A-Za-z0-9][A-Za-z0-9-]*\.md\b` |
| absolute local path | `(?<![A-Za-z0-9])[A-Za-z]:\\\|/home/[a-z]\|/Users/[A-Za-z]` |

```yaml
- name: Checkout
  uses: actions/checkout@v4

- name: Internal token scan
  uses: iyulab/dotnet-ci-actions/internal-token-scan@<commit-sha>  # pin to a commit, not @main
```

The scan refuses to pass on an empty corpus: it must read more than `min-files`
files and must have read `must-contain`, or it fails as not covering the
repository. A scanner that resolved the wrong root would otherwise find nothing
and pass forever.

**Requires**: a checked-out tree and GNU `grep` (for `-P`); `ubuntu-latest`
runners have it. Needs no `dotnet` -- place it before `setup-dotnet` or in any
job that checks out the repository.

Runs from a shell too, for the same result the job would give:

```bash
SCAN_PATH=. bash path/to/dotnet-ci-actions/internal-token-scan/scan.sh
```

| Input | Required | Default | Description |
|---|---|---|---|
| `path` | no | `.` | Directory to scan. |
| `extensions` | no | `cs,md,ts,py,csproj,props,slnx,yml,yaml,json,sh,ps1,toml,sql,graphql,xml,txt` | Comma-separated file extensions to read. |
| `include-names` | no | `Dockerfile` | Comma-separated exact file names to read as well (files with no extension). Ignore files (`.gitignore`, `.dockerignore`) are deliberately not read: naming a private directory there is how it stays private. |
| `exclude-dirs` | no | `.git,bin,obj,node_modules,dist,.venv,TestResults,coverage,claudedocs` | Comma-separated directory names pruned at any depth. |
| `extra-patterns` | no | `''` | Newline-separated extra PCRE patterns appended to the built-in set. |
| `min-files` | no | `20` | The scan must read more files than this. |
| `must-contain` | no | `README.md` | A file name that must be among the files read. |
