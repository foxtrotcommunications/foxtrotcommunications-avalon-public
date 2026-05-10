## Summary

Brief description of what this PR does.

## Type

- [ ] New OMOP model
- [ ] OMOP model fix/improvement
- [ ] New analytics package
- [ ] Package fix/improvement
- [ ] Documentation
- [ ] CI/tooling
- [ ] Forge table contract change (⚠️ requires core team approval)

## Changes

List of files changed and why.

## Testing

- [ ] `dbt run` succeeds
- [ ] `dbt test` passes
- [ ] SQL lint passes (`sqlfluff lint`)
- [ ] Package manifest validates against `packages/schema.json`
- [ ] Verified against live dataset (specify which): _______________

## Checklist

- [ ] I've read [CONTRIBUTING.md](../CONTRIBUTING.md)
- [ ] My staging models pull data only from child tables (not `root__root` scalar fields)
- [ ] My models use `{{ source() }}` with semantic names from `_sources.yml`
- [ ] I've added/updated tests in `schema.yml` for any new columns
- [ ] I haven't modified `forge-table-contract/` without explicit approval
