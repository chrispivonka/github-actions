## What changed

## Checklist for new/changed `reusable-*.yml` workflows

- [ ] Every third-party `uses:` is pinned to a full commit SHA with a `# vX.Y.Z` comment
- [ ] `permissions:` is least-privilege (top-level `contents: read` or narrower, escalated only per-job)
- [ ] Required caller permissions and recommended trigger are documented in the workflow's header comment
- [ ] A matching example exists under `examples/`
- [ ] Ran locally before pushing:
  ```
  python3 -c "import yaml, glob; [yaml.safe_load(open(f)) for f in glob.glob('.github/workflows/*.yml') + glob.glob('examples/*.yml')]"
  actionlint .github/workflows/*.yml examples/*.yml
  ```
- [ ] If this touches `docs/research/`, `docs/research/comparison.md` and `docs/site/research.html` are updated to match

Not all boxes apply to every PR (e.g. a docs-only change) — check only what's relevant.
