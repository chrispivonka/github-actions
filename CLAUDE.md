# CLAUDE.md

Context for picking up this repo cold in a future session.

## What this repo is

A library of reusable (`workflow_call`) GitHub Actions workflows, built by
researching how Apple, Google, and GitLab run CI/CD across their own
repositories, then distilling core vs. supplementary practices into ready-to-call
workflows. Remote: `git@github.com:chrispivonka/github-actions.git`.

This is a **library repo**, not an application — its "product" is the YAML in
`.github/workflows/` plus the docs that explain it. There is no build/test suite
in the traditional sense; correctness means valid, secure, well-documented
workflow YAML.

## How the repo is organized

```
.github/workflows/reusable-*.yml          the library — one workflow_call file per concern
.github/workflows/self-check.yml          dogfoods reusable-zizmor.yml + reusable-actionlint.yml on this repo's own workflows
.github/workflows/dependabot-automerge.yml  auto-merges this repo's own Dependabot PRs (see branch-protection note below)
.github/dependabot.yml                    keeps this repo's own action pins current, grouped into one PR
.github/ISSUE_TEMPLATE/, PULL_REQUEST_TEMPLATE.md
examples/*.yml                     copy-paste caller snippets, one per reusable workflow
docs/research/apple.md             Apple GH Actions research, full citations
docs/research/google.md            Google GH Actions research, full citations
docs/research/gitlab.md            GitLab CI/CD research, full citations
docs/research/comparison.md        cross-org synthesis → this library's defaults
docs/site/                         GitHub Pages docs site source (deployed via a workflow)
LICENSE                            Apache-2.0
NOTICE                             attribution for patterns + third-party Actions referenced
CONTRIBUTING.md                    short-form conventions, points back here
```

Each `reusable-*.yml` file's header comment states: which org/repo's pattern
motivated it, what permissions the caller must grant, and the recommended trigger.
Read the header before changing behavior — it's the design rationale, not
decoration.

## Conventions (apply to every new workflow)

These came directly out of the research and are load-bearing — see
[[github-actions-research-conventions]] if that memory exists, otherwise treat
this list as authoritative:

1. **SHA-pin every third-party `uses:`**, with a trailing `# vX.Y.Z` comment.
   Resolve pins with `gh api repos/<owner>/<repo>/git/ref/tags/<tag>` (dereference
   annotated tags with `git/tags/<sha>` if `object.type == "tag"`). Never trust a
   memorized SHA — re-resolve when bumping.
2. **Least-privilege `permissions:`**: top-level `contents: read` (or narrower),
   escalate only inside the job that needs it, and document why in the workflow's
   header comment.
3. **Every reusable workflow takes `workflow_call` inputs for anything a caller
   might reasonably want to override** (versions, OS list, paths, thresholds) —
   no hardcoded assumptions about the caller's stack.
4. **Document required caller permissions and trigger in a header comment**, and
   add a matching example under `examples/`.
5. **Cite the research** in the header: which repo/file motivated this design, or
   an explicit note that no example was found and the pattern was adapted from
   this repo's own conventions (see `reusable-dotnet-ci.yml` for that case — no
   .NET-heavy repos turned up in the Apple/Google samples).
6. **No Swift workflow** — the user explicitly opted out of a Swift CI workflow
   despite Swift being Apple's most heavily-instrumented ecosystem in the
   research; don't add one unless asked again.

## Research methodology (if re-running or extending)

The Apple and Google research was done by two parallel general-purpose agents
using `gh api` against the GitHub REST API — no scraping, no auth needed beyond a
`repo`-scoped token (already configured for this session). Each agent sampled
~25–45 of the org's most-starred/active public repos, listed
`.github/workflows/`, fetched representative workflow files in full, and reported
findings with every claim cited to a specific repo + filename. The GitLab
research used the public GitLab REST API (`gitlab.com/api/v4`) plus WebFetch for
GitLab's own documented CI/CD best practices, since gitlab-org isn't on GitHub in
the same way.

If asked to extend this research to a new org, replicate that method: sample by
stars/activity, don't try to be exhaustive, cite every claim, and produce both a
per-repo table and a "core vs. supplementary" distillation.

## Things to know before touching workflow files

- **`actionlint` is installed locally (via `brew install actionlint`)** — run
  `actionlint .github/workflows/*.yml examples/*.yml` before pushing any workflow
  change. `zizmor` is not installed locally (it's only invoked in CI via `uvx`);
  if you need to test a zizmor-related change, install it locally first
  (`brew install zizmor` or `uvx zizmor`) rather than pushing blind.
- **A broken-in-CI incident already happened here**: an earlier change assumed
  zizmor's CLI supported two positional scan paths in one call the way
  actionlint does; it doesn't, and it took three follow-up commits to fully
  revert (see the commit history around `reusable-zizmor.yml` /
  `self-check.yml`). Don't assume a CLI tool's calling convention — test it
  locally first, per `CONTRIBUTING.md`.
- **`dependabot-automerge.yml` depends on branch protection to mean anything.**
  It's configured (2026-07-07) with `main`'s required status checks set to
  `zizmor / Audit workflows with zizmor` and
  `actionlint / Lint workflow YAML with actionlint`, and no required-approval
  count — that's what makes "auto-merge gated on CI, regardless of approvals"
  actually true rather than a no-op. If a job in `self-check.yml` is renamed, or
  the reusable workflows it calls change their `name:`, the required-check
  strings in branch protection go stale silently (GitHub doesn't warn you) and
  auto-merge stops waiting on real results. Re-verify with
  `gh api repos/chrispivonka/github-actions/branches/main/protection` after any
  such rename.
- **`examples/*.yml` reference `chrispivonka/github-actions/.github/workflows/...@main`.**
  If this repo is ever forked/renamed, or once it starts cutting tagged releases,
  update the `uses:` refs in every example (and in this file) to match — `@main`
  is a placeholder for "not yet versioned," not a permanent choice.
- **The GitHub Pages docs site is deployed by its own workflow** (see
  `.github/workflows/` for the pages-deploy workflow) — changes to `docs/site/`
  don't show up on chrispivonka.github.io until that workflow runs on push to
  main.
- **`.claude/settings.local.json` and `.claude/scheduled_tasks.lock` exist in this
  repo** but are unrelated to the workflow library itself — Claude Code session
  config, not part of the product.
