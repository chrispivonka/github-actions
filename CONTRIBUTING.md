# Contributing

This repo is a library of reusable GitHub Actions workflows. See
[`CLAUDE.md`](CLAUDE.md) for the full context and design rationale — this file is
the short version for anyone opening a PR.

## Adding or changing a reusable workflow

Every file in `.github/workflows/reusable-*.yml` follows the same shape. When
adding a new one or editing an existing one:

1. **SHA-pin every third-party `uses:`**, with a trailing `# vX.Y.Z` comment.
   Resolve the pin yourself — don't guess or reuse a memorized SHA:
   ```
   gh api repos/<owner>/<repo>/git/ref/tags/<tag> --jq '.object.type + " " + .object.sha'
   # if object.type == "tag" (annotated tag), dereference it:
   gh api repos/<owner>/<repo>/git/tags/<sha> --jq .object.sha
   ```
2. **Least-privilege `permissions:`** — top-level `contents: read` (or narrower),
   escalate only inside the job that needs more.
3. **Typed `workflow_call` inputs** for anything a caller might reasonably want to
   override (versions, OS list, paths, thresholds) — don't hardcode assumptions
   about the caller's stack.
4. **Document the required caller `permissions:` block and recommended trigger**
   in a header comment, and cite the research pattern that motivated the design
   (or note explicitly that none applied, as `reusable-dotnet-ci.yml` does).
5. **Add a caller example** under `examples/`, matching the naming of the
   reusable workflow (`reusable-foo.yml` → `examples/foo.yml`).
6. **Test locally before pushing.** This library has already had a broken-in-CI
   incident from skipping this step — see the commit history around
   `reusable-zizmor.yml` for what that looked like. At minimum:
   ```
   python3 -c "import yaml, glob; [yaml.safe_load(open(f)) for f in glob.glob('.github/workflows/*.yml') + glob.glob('examples/*.yml')]"
   actionlint .github/workflows/*.yml examples/*.yml   # brew install actionlint
   ```
   If your change touches a tool invoked by `run:` steps (like zizmor or
   actionlint itself), test that tool's actual CLI behavior locally — don't
   assume it supports the same calling convention as a similar tool.

## Everything in this repo is checked automatically

`self-check.yml` runs both `reusable-zizmor.yml` (security) and
`reusable-actionlint.yml` (schema/syntax) against this repo's own workflow files
on every push and PR. `dependabot.yml` keeps the SHA pins in `.github/workflows/`
current — it won't touch `examples/`, since Dependabot's `github-actions`
ecosystem doesn't scan arbitrary directories, so bump those manually if you
change a pinned version.

## Research changes

If you're extending `docs/research/` to a new organization, follow the existing
method (see `CLAUDE.md`'s "Research methodology" section): sample by
stars/activity rather than trying to be exhaustive, cite every claim to a
specific repo and file, and produce both a per-repo table and a "core vs.
supplementary" distillation. Update `docs/research/comparison.md` and
`docs/site/research.html` to reflect any new convergence or divergence found.

## What not to do

- Don't add a workflow "because an org does it" without a caller use case in
  mind — see the README's "Supplementary" section for what's meant to be
  adopted case by case rather than by default.
- Don't skip the local-testing step because a change "looks right." YAML that
  parses is not the same as YAML that runs correctly under the tool it invokes.
