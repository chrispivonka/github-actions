# github-actions

A library of modular, reusable [GitHub Actions](https://docs.github.com/en/actions)
workflows — built by researching how [Apple](https://github.com/apple) and
[Google](https://github.com/google) run CI/CD across their public repositories (and
how [GitLab](https://about.gitlab.com/) structures its own CI/CD pipelines), then
distilling what both treat as **core** (near-universal, high-leverage) versus
**supplementary** (valuable, but adopted case by case) into ready-to-call
`workflow_call` workflows.

**Docs site:** https://chrispivonka.github.io/github-actions/ — full usage guide for
every workflow, inputs/outputs, and the research writeups.

## Why this exists

Rolling your own CI setup from scratch means re-deriving decisions that large
engineering orgs have already made — and often gotten wrong once before fixing.
This repo packages those decisions as reusable workflows so a new or existing repo
can adopt them with a five-line caller file instead of a hundred-line one, while
staying free to override any input.

The design choices here are traceable to specific patterns observed in the
research (see [`docs/research/`](docs/research/)):

- **SHA-pin every third-party action, with a version comment** — the practice
  correlates almost exactly with which repos run OpenSSF Scorecard in both the
  Apple and Google samples.
- **Least-privilege `permissions:` blocks**, declared at the top level and
  escalated only per-job — used in the large majority of workflows sampled from
  both orgs.
- **Concurrency groups with `cancel-in-progress`** on PR pipelines, so superseded
  runs don't waste minutes.
- **`persist-credentials: false` on checkout** wherever the job doesn't need to
  push — observed extensively in newer workflows from both orgs.
- **Reusable-workflow centralization**: one team maintains the CI logic; consumers
  are thin callers. This is exactly the `swiftlang/github-workflows` +
  `apple/swift-nio` pattern, and the `google/osv-scanner-action` pattern, applied
  to this repo's own structure.

## What's here

```
.github/workflows/   the reusable workflows (workflow_call) — the actual library
examples/            copy-paste caller snippets for every reusable workflow
docs/research/       the research this library is based on
docs/site/           source for the GitHub Pages documentation site
LICENSE              Apache-2.0
NOTICE               attribution for third-party patterns and actions referenced
```

## Quick start

Pick a workflow, copy its example caller from `examples/` into your repo's
`.github/workflows/`, and adjust the inputs. Every reusable workflow documents its
required caller `permissions:` block in a header comment — copy it exactly; it's
already least-privilege.

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  ci:
    uses: chrispivonka/github-actions/.github/workflows/reusable-go-ci.yml@main
    permissions:
      contents: read
    with:
      go-versions: '["1.23", "1.24"]'
```

Pin `@main` to a tag or commit SHA once this repo starts cutting releases, the same
way `swift-collections` pins `swiftlang/github-workflows@0.0.12` rather than
tracking a branch.

## Workflow catalog

### Core — language-agnostic (adopt on nearly every repo)

| Workflow | What it does | Modeled on |
|---|---|---|
| [`reusable-codeql.yml`](.github/workflows/reusable-codeql.yml) | Static analysis via CodeQL, SARIF → code scanning. Can scan the `actions` language, i.e. your workflow files. | apple/pkl, google/gson, google/brotli |
| [`reusable-dependency-review.yml`](.github/workflows/reusable-dependency-review.yml) | Fails PRs introducing vulnerable or disallowed-license dependencies. | google/libphonenumber |
| [`reusable-scorecard.yml`](.github/workflows/reusable-scorecard.yml) | OpenSSF Scorecard supply-chain security score, badge, and SARIF upload. | google/guava, google/gson, google/brotli, google/magika (39 repos in the Google sample) |
| [`reusable-zizmor.yml`](.github/workflows/reusable-zizmor.yml) | Statically audits your workflow files themselves for injection/permission/pinning issues. | google/zx, google/osv-scanner |
| [`reusable-stale.yml`](.github/workflows/reusable-stale.yml) | Marks and closes inactive issues/PRs on a schedule. | google/flatbuffers, apple/foundationdb |
| [`reusable-labeler.yml`](.github/workflows/reusable-labeler.yml) | Path-based auto-labeling for PRs, including forked PRs. | google/flatbuffers, google/gvisor |
| [`reusable-release-please.yml`](.github/workflows/reusable-release-please.yml) | Conventional-commit release automation: running release PR → tagged GitHub release. | google/dotprompt, google/adk-python family |
| [`reusable-github-release.yml`](.github/workflows/reusable-github-release.yml) | Publishes a (draft, by default) GitHub Release with build artifacts attached. | apple/container, google/jsonnet |

### Per-language CI (adopt the one matching your stack)

| Workflow | Stack | Stages |
|---|---|---|
| [`reusable-node-ci.yml`](.github/workflows/reusable-node-ci.yml) | Node.js / TypeScript | install → lint → typecheck → test → build, across a Node-version × OS matrix |
| [`reusable-python-ci.yml`](.github/workflows/reusable-python-ci.yml) | Python (via `uv`) | ruff check → ruff format → pytest, across a Python-version matrix |
| [`reusable-go-ci.yml`](.github/workflows/reusable-go-ci.yml) | Go | vet → golangci-lint → test (race + coverage), across a Go-version matrix |
| [`reusable-rust-ci.yml`](.github/workflows/reusable-rust-ci.yml) | Rust | fmt --check → clippy -D warnings → test, across a toolchain matrix |
| [`reusable-dotnet-ci.yml`](.github/workflows/reusable-dotnet-ci.yml) | C# / .NET | restore → format check → build → test, across an SDK-version matrix |

Every CI workflow takes `os` and its version-axis input as JSON arrays, so a caller
gets a full matrix build for free — the same shape as Apple's
`swift_package_test.yml` and Google's per-language build matrices, just scoped to
one language per workflow instead of one mega-workflow.

### Supplementary (adopt case by case)

Not every workflow belongs in every repo. The research is explicit about this:
Apple's `ml-*` research-code repos run zero CI, and Google's benchmark/fuzzing/SLSA
workflows appear only on a minority of repos even within actively-maintained OSS.
Treat these as available, not mandatory:

- **CodeQL / Scorecard / dependency-review** are cheap enough to be near-default,
  but skip them on archived or non-code repos.
- **release-please / github-release** only apply if you actually cut versioned
  releases.
- **Per-language CI** — only add the one matching your stack; don't stack
  multiple language workflows unless the repo is genuinely polyglot (see
  `google/magika`'s per-language pattern in the research for how that's structured
  when it's warranted).
- **stale / labeler** matter most on high-traffic repos with real triage burden;
  skip them on low-traffic or internal-only repos where they'd just add noise.

## Research

The full writeups, with per-repo citations for every claim:

- [`docs/research/apple.md`](docs/research/apple.md) — Apple's org-wide patterns:
  the `swiftlang/github-workflows` + `apple/swift-nio` reusable-workflow hubs, the
  soundness-gate pattern, and the split between maintained-product CI and
  zero-CI research-code drops.
- [`docs/research/google.md`](docs/research/google.md) — Google's org-wide
  patterns: the security-tooling layer (Scorecard/CodeQL/harden-runner/zizmor),
  scorecard-driven SHA-pinning adoption, and dogfooding (osv-scanner scanning
  Google's own repos, ADK agents triaging their own issues).
- [`docs/research/gitlab.md`](docs/research/gitlab.md) — GitLab's own CI/CD
  structure as a third data point: its mega-pipeline architecture, the CI/CD
  Components Catalog (GitLab's analog to reusable workflows), predictive/tiered
  test selection, and a GitLab-CI-to-GitHub-Actions concept mapping.
- [`docs/research/comparison.md`](docs/research/comparison.md) — cross-org
  synthesis: seven practices where Apple, Google, and GitLab independently
  converge (least-privilege permissions, reusable-workflow centralization,
  cancel-superseded-not-mainline concurrency, fork-safety guards, gated releases,
  toggle-able security scanning, dogfooding), and where they diverge.

## Licensing and attribution

This repo is licensed under [Apache-2.0](LICENSE). See [`NOTICE`](NOTICE) for
attribution of the third-party GitHub Actions this library wraps and the
open-source workflows that informed its design.

## Contributing

Adding a new reusable workflow? Follow the existing pattern: SHA-pin every
`uses:`, document the required caller `permissions:` in a header comment, cite the
research pattern that motivated it (or note that none applied), and add a caller
example under `examples/`. See [`CLAUDE.md`](CLAUDE.md) for the full set of repo
conventions.
