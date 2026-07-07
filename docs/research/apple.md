# How Apple Uses GitHub Actions (github.com/apple)

> Research conducted July 2026 by surveying ~45 of Apple's most-starred/active public
> repositories via the GitHub API — listing `.github/workflows/` for each and reading
> ~57 workflow files in full. Every claim cites a repo and filename. Findings reflect a
> point-in-time snapshot; upstream workflows evolve.

## Org-wide summary

Apple's public GitHub presence splits into **three sharply distinct tiers** of CI behavior:

1. **The Swift library ecosystem** (~20 repos: `swift-nio`, `swift-log`, `swift-crypto`,
   `swift-collections`, `swift-protobuf`, …) — heavy, highly standardized GitHub Actions
   usage built almost entirely on **two hubs of reusable workflows**:
   [`swiftlang/github-workflows`](https://github.com/swiftlang/github-workflows) (the Swift
   project's shared CI repo — note `apple/swift` itself and `sourcekit-lsp` have moved to
   the `swiftlang` org) and, remarkably,
   [`apple/swift-nio`](https://github.com/apple/swift-nio) acting as a de facto second
   central CI repo whose `.github/workflows/*.yml` are consumed cross-repo via
   `workflow_call`.
2. **Product/platform repos** (`container`, `containerization`, `pkl`, `servicetalk`,
   `foundationdb`, `coreai-models`, `embedding-atlas`) — bespoke, self-contained GHA
   pipelines, several on **self-hosted macOS runners**.
3. **ML research repos** (`ml-*`) — **no CI at all**. `ml-ferret`, `ml-sharp`,
   `ml-fastvlm`, `ml-depth-pro`, `ml-mobileclip`, `ml-stable-diffusion`, `corenet`,
   `turicreate`, plus `darwin-xnu`, `cups`, `security-pcc`, and `python-apple-fm-sdk` all
   have no `.github/workflows` directory. These are code drops, not maintained-with-CI
   projects.

**GitHub Actions vs. external CI:**

- `apple/coremltools` has no workflows but a `.gitlab-ci.yml` at repo root — it runs
  entirely on GitLab CI.
- `apple/foundationdb` uses GHA only for lint/format/stale/one Windows Boost smoke test
  (`format.yml`, `tidy.yml`, `stale.yml`, `windows-boost-test.yml`); its real
  correctness/simulation testing runs on internal infrastructure.
- The Swift compiler's Jenkins-based "Swift CI" (`@swift-ci`) lives with the `swiftlang`
  org, not `apple`. Within `apple/*`, for the repos that have CI, **GitHub Actions is the
  primary and usually sole public CI**.
- The org-level `apple/.github` repo contains only `CODE_OF_CONDUCT.md` and `SECURITY.md`
  — no org-wide default workflows.

## The reusable-workflow architecture (the defining pattern)

### `swiftlang/github-workflows` — the shared soundness/test hub

Two workflows dominate:

**`soundness.yml`** (consumed by 11+ sampled callers) bundles ten opt-out checks, each a
separate job:

- API breakage check (`swift package diagnose-api-breaking-changes` in a container)
- DocC docs-build check (Linux + optional self-hosted-macOS variant)
- Unacceptable-language check (grep against a default word list)
- License-header check (parameterized by project name)
- Broken-symlink check
- `swift-format` check
- shellcheck, yamllint, Python lint

It defines its own concurrency group
(`${{ github.workflow }}-${{ github.ref }}-soundness-…`, `cancel-in-progress: true`).

**`swift_package_test.yml`** is a mega-matrix reusable workflow covering macOS (multiple
Xcode versions on self-hosted runners), Linux (Swift 5.9 → nightly across
`jammy`/`rhel-ubi9`/`amazonlinux2023`, x86_64 + aarch64), Windows, Static Linux SDK
(musl), Wasm SDK, Embedded Wasm, Android SDK, and even FreeBSD — all driven by
JSON-string inputs like `linux_exclude_swift_versions: '[{"swift_version": "5.9"}]'`
(see `apple/swift-collections` `pull_request.yml` for the fullest example).

Callers pin it either to a tag (`@0.0.10`/`@0.0.12` — swift-nio, swift-log,
swift-collections), to `@main` (swift-algorithms, swift-container-plugin), or to a
**full SHA with a tag comment** (`apple/swift-homomorphic-encryption` `ci.yml`:
`uses: swiftlang/github-workflows/.github/workflows/soundness.yml@0793626… # 0.0.12`).

### `apple/swift-nio` — a second, richer CI hub

swift-nio hosts 17 workflows, most of which are `workflow_call` reusables consumed by
other Apple repos (`swift-log`, `swift-crypto`, `swift-metrics`,
`swift-openapi-generator`, `swift-container-plugin`, `swift-distributed-tracing`,
`swift-http-types`, `swift-asn1`, `swift-certificates` all do
`uses: apple/swift-nio/.github/workflows/…@main`):

- `unit_tests.yml` / `swift_matrix.yml` / `swift_test_matrix.yml` — Swift-version
  matrices (5.9 → 6.3 → nightly; Linux in `swift:X-jammy` containers, Windows optional
  per version). Distinctive mechanism: matrices are generated dynamically by curl-ing a
  script from swift-nio's main branch into bash — org-wide behavior is changeable by
  editing one script (efficient, but a notable supply-chain trust decision).
- `benchmarks.yml` / `macos_benchmarks.yml` — package-benchmark threshold checks per
  Swift version.
- `cxx_interop.yml` — builds with C++ interoperability enabled across the Linux matrix.
- `swift_6_language_mode.yml` — checks packages compile in Swift 6 language mode.
- `macos_tests.yml` — runs on `[self-hosted, macos, <os>, <arch>, <pool>]` runners with
  named runner pools (`general` for PRs, `nightly` for scheduled runs) and per-Xcode
  toggles, including xcodebuild tests for iOS/watchOS/tvOS/visionOS.
- `static_sdk.yml`, `wasm_swift_sdk.yml`, `android_swift_sdk.yml`, `release_builds.yml`
  — cross-platform SDK build verification.
- Nearly every `uses:` line carries a comment noting a workaround for
  [nektos/act#1875](https://github.com/nektos/act/issues/1875) — they keep workflows
  runnable locally under `act`.

### A third hub: shared release automation

`apple/swift-log` `auto-release.yml` (also swift-metrics, swift-distributed-tracing,
swift-openapi-generator) is a one-liner:
`uses: apple/swift-temporal-sdk/.github/workflows/auto-release.yml@main`, triggered by
`workflow_dispatch` with `contents: write` — shared tag/release automation.

## Workflow categories observed

| Category | Evidence |
|---|---|
| **Build/test matrices** | swift-nio `unit_tests.yml` (Linux 6.0–nightly + Windows); swift-protobuf `build.yml` (Swift 6.1/6.2/6.3 × 4 package-trait combos in containers); servicetalk `ci-prb.yml` (JDK 8/11/17/21/25 on ubuntu + JDK 11 self-hosted macOS); pkl `build.yml` (ubuntu/windows/`ubuntu-24.04-arm`) |
| **Soundness/lint/format** | `soundness.yml` suite across all Swift libs; foundationdb `format.yml` (clang-format, `git diff --exit-code`) and `tidy.yml` (clang-tidy on changed files only, in a project container); axlearn `pre-commit.yml`; coreai-models `ci.yml` (ruff + `swift format lint --strict`); password-manager-resources `lint.yml` (whitespace greps, JSON sort-order checks) |
| **API breakage checks** | soundness.yml's `api-breakage-check` job, selectively disabled with issue-link comments (swift-collections disables it citing its issue #435) |
| **Docs (DocC)** | soundness.yml `docs-check`; containerization `docs-release.yaml` deploys DocC to GitHub Pages via `actions/upload-pages-artifact` + `actions/deploy-pages` |
| **Release/publish** | apple/container `release.yml` (semver-tag-triggered, builds signed .pkg/.zip on self-hosted macOS, publishes a **draft prerelease** via `softprops/action-gh-release`); embedding-atlas `ci.yml` (on `release: published` → **PyPI trusted publishing** with `environment: pypi` + `pypa/gh-action-pypi-publish`, and `npm publish --provenance`); shared `auto-release.yml` |
| **Security scanning** | CodeQL only on non-Swift repos: pkl/pkl-go/pkl-swift `codeql.yml` (notably scans `languages: actions` — CodeQL analysis *of the workflows themselves* — weekly cron) and servicetalk `codeql-analysis.yml` (java, weekly cron, `security-events: write` scoped to the job). **No OpenSSF Scorecard found in any sampled Apple repo.** servicetalk runs `gradle/actions/wrapper-validation` as a gate before every build |
| **Stale/triage bots** | foundationdb `stale.yml` (PRs stale at 150 days, close +14; issues effectively disabled); container `pr-label-analysis.yml`/`pr-label-apply.yml` (two-stage artifact-passing labeler that avoids `pull_request_target` foot-guns); swift-nio et al. `pull_request_label.yml` (**semver label check** via a local composite action, `timeout-minutes: 1`) |
| **Benchmark/regression** | swift-nio `benchmarks.yml` + `macos_benchmarks.yml` (package-benchmark thresholds); swiftlang/github-workflows `performance_test.yml` |
| **Dependency automation** | swift-protobuf `update_protobuf.yml` — nightly cron that re-vendors protobuf/abseil and opens a PR, deliberately letting CI fail as "a notice that something needs to be done"; swiftlang/github-workflows hosts `github_actions_dependencies.yml` and `create_automerge_pr.yml` |

## Structural patterns and hygiene

- **`permissions:` blocks are near-universal**: 54 of 57 sampled files declare top-level
  permissions, almost always `permissions: contents: read`, with job-level escalation
  only where needed (container `release.yml` job gets `contents: write`; servicetalk's
  CodeQL job gets `security-events: write`). Only legacy files (HomeKitADK's 2020-era
  `linux-ci.yml`, still on `ubuntu-18.04` + `actions/checkout@v1`) lack them.
- **SHA-pinning dominates**: 491 `uses:` references pinned to full 40-char SHAs with a
  version comment (e.g. `actions/checkout@9c091bb2… # v7.0.0`) vs. 160 tag/branch refs.
  The tag/branch refs are mostly *intra-Apple* reusable-workflow calls
  (`apple/swift-nio/...@main`, `swiftlang/github-workflows/...@0.0.12`) — trusted
  internal sources.
- **`apple/pkl` generates its workflows from Pkl**: every pkl/pkl-go/pkl-swift workflow
  begins `# Generated from Workflow.pkl. DO NOT EDIT.` — Apple dogfoods its own config
  language to produce Actions YAML, complete with a lockfile workflow.
- **`persist-credentials: false` on checkout** in 21 files (all newer Swift-ecosystem and
  container workflows) — deliberate token hygiene.
- **Concurrency groups** (`group: ${{ github.workflow }}-${{ github.ref }}`,
  `cancel-in-progress: true`) in pkl (all workflows; disabled for build/release),
  swift-homomorphic-encryption, coreai-models, and inside the shared soundness/matrix
  reusables — with a `concurrency_group_suffix` input so multiple matrix callers in the
  same repo don't cancel each other.
- **Self-hosted macOS fleet**: labels follow `[self-hosted, macos, <os-name>, <arch>,
  <pool>]` with pool names `general` and `nightly`. Linux/Windows jobs use GitHub-hosted
  runners.
- **Fork guards**: `if: github.repository == 'apple/container'` (also coreai-models,
  swift-protobuf's bot) so self-hosted/secret-bearing jobs never run on forks.
- **Containers over setup actions** for Swift: Linux jobs run *inside* `swift:6.x-noble`
  or nightly toolchain images rather than installing toolchains on the runner.
- **`timeout-minutes` discipline** on self-hosted jobs (container: 75; coreai-models:
  15/60; the semver label check: 1).

## Trigger patterns

- **The Swift-ecosystem convention**: a `pull_request.yml` on
  `pull_request: types: [opened, reopened, synchronize]` (explicit types everywhere),
  plus a `main.yml` on `push: branches: [main]` **and** `schedule: cron: "0 8,20 * * *"`
  (twice-daily full matrix including nightly toolchains), plus a label-triggered semver
  check, plus `workflow_dispatch`-only release automation.
- pkl splits by branch topology: `build.yml` on
  `branches-ignore: [main, release/*, dependabot/**]`, `main.yml` on main, `release.yml`
  on tags only.
- servicetalk uses aggressive `paths-ignore` lists (docs, scripts, `**.adoc`) to skip CI
  on non-code changes.
- Cron bots: foundationdb stale (daily), swift-protobuf dependency update (nightly),
  CodeQL weekly crons (pkl, servicetalk).
- axlearn is the only sampled repo using `merge_group` (merge-queue) triggers.

## Distinctive / opinionated findings

1. **swift-nio as shared infrastructure** — an application library doubling as the org's
   CI framework, consumed by ~10 sibling repos at `@main` (unpinned, trusted internally).
2. **The soundness suite's unacceptable-language check**, with a self-annotated default
   word list.
3. **Kernel-level test creativity**: swift-nio's `pull_request.yml` has a `vsock-tests`
   job that runs `sudo modprobe vsock_loopback` on the GitHub runner, then greps output
   to fail if tests were silently skipped.
4. **apple/container's `verify-signatures` job** — hard-fails PRs containing any unsigned
   commit, via `gh api …/pulls/N/commits` + jq over `commit.verification.verified`.
5. **swift-algorithms' `validate_format_config`** — diffs its `.swift-format` against a
   canonical copy in another repo to keep format configs org-consistent.
6. **CodeQL scanning of workflow files themselves** (`languages: actions`) in pkl repos.
7. **Cross-platform ambition**: Swift libraries routinely CI against Linux (multiple
   distros/arches), Windows, all Apple platforms, Static-musl SDK, WebAssembly, Android,
   and FreeBSD.

## What Apple treats as core vs. supplementary

**Core (invested-in, standardized, enforced):**

- The **soundness gate** — license headers, formatting, docs-build, API-stability,
  language hygiene — is the single most consistently applied CI element across Swift
  repos; it's versioned, shared, and opt-out-with-issue-link only.
- **Cross-platform build/test matrices** across language versions *and* exotic targets —
  treated as a release-blocking concern, not a nice-to-have.
- **Reusable-workflow centralization** — one team maintains the CI logic; consumers are
  thin ~50-line callers.
- **Least-privilege permissions + SHA pinning** for anything touching third-party
  actions.
- **Self-hosted capacity with pool scheduling** for platform testing GitHub-hosted
  runners can't provide.

**Supplementary (present but uneven):**

- **Security scanning**: CodeQL only where individual teams chose it; no Scorecard; no
  org-wide mandate; Dependabot visible only in pkl.
- **Benchmarking** (swift-nio/swift-log only), **stale bots** (foundationdb/axlearn
  only), **release automation** (per-team styles: draft prereleases, trusted publishing,
  generated pipelines).
- **CI at all for research code**: the entire `ml-*` catalog ships with zero automation —
  GitHub Actions is core to Apple's *maintained open-source products* and simply absent
  from its *paper-artifact drops*.

## Repos consulted

`swift-nio`, `swift-log`, `swift-metrics`, `swift-crypto`, `swift-openapi-generator`,
`swift-distributed-tracing`, `swift-http-types`, `swift-asn1`, `swift-certificates`,
`swift-collections`, `swift-algorithms`, `swift-argument-parser`, `swift-numerics`,
`swift-system`, `swift-container-plugin`, `swift-homomorphic-encryption`,
`swift-protobuf`, `swift-temporal-sdk`, `container`, `containerization`, `pkl`,
`pkl-go`, `pkl-swift`, `servicetalk`, `foundationdb`, `coreai-models`,
`embedding-atlas`, `axlearn`, `password-manager-resources`, `HomeKitADK`,
`coremltools`, and the no-CI set (`ml-ferret`, `ml-sharp`, `ml-fastvlm`, `ml-depth-pro`,
`ml-mobileclip`, `ml-stable-diffusion`, `corenet`, `turicreate`, `darwin-xnu`, `cups`,
`security-pcc`, `python-apple-fm-sdk`), plus `swiftlang/github-workflows` and the
org-level `apple/.github`.
