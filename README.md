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
  uses: iyulab/dotnet-ci-actions/vulnerability-scan@main
```

With an explicit solution/project file:

```yaml
- name: Vulnerability scan
  uses: iyulab/dotnet-ci-actions/vulnerability-scan@main
  with:
    project: MySolution.slnx
```

**Requires**: dependencies already restored (`dotnet restore` run earlier in the
job) and `dotnet` on `PATH` (e.g. via `actions/setup-dotnet`).

| Input | Required | Default | Description |
|---|---|---|---|
| `project` | no | `''` | Path to a solution or project file. Left empty, `dotnet` discovers the single solution/project in the current directory. |
