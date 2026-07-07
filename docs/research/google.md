# How Google Uses GitHub Actions (github.com/google)

> Research conducted July 2026 by sampling 38 of Google's most-starred/most-active public
> repositories (spanning Java, C++, Go, Python, Rust, JS/TS, Kotlin), enumerating
> `.github/workflows/` in each via the GitHub API, reading 66 workflow files in depth,
> inspecting the org-level `google/.github` repo, and running org-wide code searches for
> prevalence numbers. Code-search counts are approximate matching-file counts across the
> org's ~2,000 repos. Findings reflect a point-in-time snapshot.

## Org-wide summary

- **GitHub Actions is the default public CI** for actively maintained Google OSS. 34 of
  38 sampled repos have workflows; the four without them (`googletest`, `skia`,
  `sanitizers`, `guetzli`) are either internal-CI-driven mirrors or dormant.
- **Internal CI still coexists visibly.** `kokoro` paths appear in ~350 files org-wide;
  `googletest` ships only Kokoro-style presubmit scripts with no workflows; `skia` is a
  Gerrit/LUCI project mirror; `gvisor` keeps its real pipeline in **BuildKite** and uses
  Actions only for a smoke build, a `go`-branch generator, and hygiene bots. Several
  repos are Copybara-synced from google3 (23 `.github` files reference copybara).
- **Security automation is the most consistent org-wide layer:** OpenSSF Scorecard
  (39 workflow files), CodeQL (41), step-security harden-runner (64), OSV-Scanner
  reusable workflows (14), zizmor (15), dependency-review (7), SLSA provenance (6), plus
  a distinctive **org-level semgrep scan of workflow files themselves** in
  `google/.github`.
- **There is no single org-mandated CI template** — per-repo styles vary hugely (compare
  `or-tools`' 36 workflow files vs. `wire`'s one) — but the security tooling, the
  SHA-pin-with-version-comment style, and least-privilege `permissions:` blocks recur so
  often they clearly come from shared guidance/tooling (permission-justifying comments
  are verbatim-identical across repos).

## Prevalence of Actions vs. internal CI

| Repo | Public CI story |
|---|---|
| `googletest` | No workflows. `ci/*-presubmit.{sh,bat}` scripts run by internal Kokoro |
| `skia` | No workflows. Chromium-infra project: Gerrit + LUCI CQ (`PRESUBMIT.py`, `DEPS`) |
| `gvisor` | Hybrid: BuildKite for real CI; Actions only for smoke `build.yml`, `go.yml` (generates the `go` branch with a dedicated `GO_TOKEN` secret), stale/labeler/CodeQL |
| `adk-python` | Actions for everything public, plus `copybara-pr-handler.yml` — auto-closes PRs that were merged through Google's internal Copybara sync |
| `guava`, `gson`, `error-prone`, `truth`, `guice`, `dagger`, `auto` | Fully Actions-based (Java family) |
| `oss-fuzz`, `osv-scanner`, `go-github`, `flatbuffers`, `benchmark`, `or-tools`, `filament`, `magika` | Fully Actions-based |

Notably, **zero workflows implement CLA checking** — CLA enforcement is the external
`googlebot` GitHub App (cla.developers.google.com), entirely outside Actions.
Google-internal vocabulary leaks into workflow naming: `presubmit.yml` /
`postsubmit.yml` (`filament`, `or-tools`, `oss-fuzz`), mirroring google3 terminology.

## Workflow categories with concrete examples

### Build/test matrices (the workhorse)

- **`leveldb/build.yml`** — classic 3-axis matrix
  `compiler: [clang, gcc, msvc] × os × optimized: [true, false]` with `exclude:` blocks
  removing invalid combos and `include:` injecting `CC/CXX` env per compiler.
- **`guava/ci.yml`** — `java: [8, 11, 17, 25] × root-pom: ['pom.xml',
  'android/pom.xml']` plus a Windows include; separate test and snapshot-publish jobs.
- **`error-prone/ci.yml`** — tests JDK **early-access builds** with
  `experimental: true` + `continue-on-error: ${{ matrix.experimental }}`, with a comment
  explaining they deliberately avoid combinatorial explosion.
- **`or-tools`** — the extreme case: **36 workflow files**, one per
  `arch_os_buildsystem_language` combo, with a single `presubmit.yml` (clang-format +
  Bazel on 4 OSes) gating PRs. Hand-rolled `actions/cache/restore` + `save` for ccache.
- **`benchmark/build-and-test.yml`** — `os × build_type × compiler × lib(shared/static)`,
  plus dedicated `sanitizer.yml` (ASan/UBSan/TSan), `bazel.yml`, `wheels.yml`.
- **`filament/presubmit.yml`** — beefy paid runners (`macos-14-xlarge`,
  `arm-ubuntu-24.04-16core`) and a clever `check-verification` job: presubmit is skipped
  on pushes to main whose commit is cryptographically "verified" (i.e., a GitHub
  squash-merge that already passed PR presubmit).
- **`dagger/ci.yml`** — runner groups (`runs-on: {group: large-runner-group, labels:
  ubuntu-22.04-16core}`), heavy use of local composite actions.
- **`magika`** — per-language workflows in a polyglot repo: `python-test-suite.yml`,
  `rust-test.yml`, `go-test.yml`, `js-test.yml`, `website-test.yml`.

### Lint/format

`or-tools/presubmit.yml` (clang-format action), `benchmark/pre-commit.yml` +
`clang-tidy-lint.yml`, `yapf/ci.yml` + `pre-commit-autoupdate.yml`,
`go-github/linter.yml` (golangci-lint), `osv-scanner/checks.yml` (lint + prettier),
`langextract` (a whole PR-hygiene suite: `check-pr-size.yml`,
`validate_pr_template.yaml`, `check-linked-issue.yml`, `check-pr-up-to-date.yaml`).

### Release automation

- **release-please**: 30 workflow files org-wide, concentrated in newer repos
  (`dotprompt`, the `adk-*` family, `gts`, `re2-wasm`, `slo-generator`). `adk-python`
  layers a bespoke multi-track pipeline on top: `release-cut.yml` (workflow_dispatch
  with `choice` inputs, cuts `release/v*-candidate` branches), `release-finalize.yml`,
  `release-publish.yml`, `release-cherry-pick.yml`.
- **SLSA provenance**: `flatbuffers/release.yml` and `osv-scanner/goreleaser.yml` both
  call
  `slsa-framework/slsa-github-generator/.github/workflows/generator_generic_slsa3.yml@v2.1.0`
  with `id-token: write` to sign provenance over base64 subject hashes.
- **goreleaser** (`osv-scanner/goreleaser.yml` + nightly variant),
  **softprops/action-gh-release** (`jsonnet/release.yml`, workflow_dispatch-driven with
  a `prerelease` boolean input and draft releases), npm/JSR publishing (`zx`), PyPI
  (`jsonnet`, `magika` — which also runs **post-release verification workflows** that
  test the published package), crates.io (`comprehensive-rust`), Bazel Central Registry
  (`brotli/publish_to_bcr.yaml`), container images (`cadvisor/publish-container.yml`).

### Security scanning (the most uniform layer)

- **OpenSSF Scorecard** — 39 files (`guava/scorecard.yml`, `gson`, `brotli`, `magika`,
  `libphonenumber/scorecards.yml`, `osv-scanner`, `closure-compiler`,
  `benchmark/ossf.yml`, …). All are the canonical template: triggers
  `branch_protection_rule` + weekly cron + push to default branch;
  `permissions: read-all` at top; job-level `security-events: write` +
  `id-token: write`; `publish_results: true` (badge); SARIF upload to code scanning.
- **CodeQL** — 41 files (`zx`, `gvisor`, `gson`, `brotli`, `magika`, `libphonenumber`,
  `oss-fuzz`, `osv-scanner`).
- **OSV-Scanner (dogfooding their own product)** — the `osv-scanner` repo *publishes*
  reusable workflows (`on: workflow_call` with typed inputs `scan-args`,
  `fail-on-vuln`; now maintained in `google/osv-scanner-action`). Consumers like
  `libphonenumber/osv-scanner-unified.yml` call it cross-repo, SHA-pinned:
  `uses: "google/osv-scanner-action/.github/workflows/osv-scanner-reusable-pr.yml@8bd1ce1… # v1.9.1"`.
  The reusable workflow's header documents the exact `permissions:` block callers must
  copy.
- **harden-runner** — 64 files org-wide (`libphonenumber/dependency-review.yml` runs
  `step-security/harden-runner` with `egress-policy: audit # TODO: change to block`;
  also `brotli`, `zerocopy`, `highway`, `gemma.cpp`, `jpegli`).
- **dependency-review** — 7 files (e.g. `libphonenumber/dependency-review.yml` on every
  `pull_request`).
- **zizmor (linting the workflows themselves)** — 15 files. `zx/zizmor.yml`:
  `permissions: {}` at top, job gets `contents: read` + `actions: read`, runs
  `uvx zizmor@1.22.0 .github/workflows -v -p --min-severity=medium`.
- **Org-level `google/.github`** contains `action_scanning.yml`: a **semgrep scan of
  every repo's workflow files** with org-custom rules — including
  `pull_request_target_needs_exception.yml`, i.e. Google treats `pull_request_target`
  as requiring an explicit exception. SARIF goes to the security dashboard.
- **`persist-credentials: false`** on checkout appears in 136 workflow files org-wide.

### Fuzzing

- **CIFuzz** (17 files): `gson/cifuzz.yml` and `sentencepiece/cifuzz.yml` use
  `google/oss-fuzz/infra/cifuzz/actions/{build_fuzzers,run_fuzzers}@master` (600s,
  SARIF output). The pin is `@master` with an apologetic comment: *"Cannot be pinned to
  commit because there are no releases, see google/oss-fuzz#6836"* — the exception that
  proves the SHA-pinning rule.
- **ClusterFuzzLite**: `oss-fuzz/cflite_pr.yml` fuzzes oss-fuzz's own infra on PRs
  (sanitizer matrix, per-sanitizer concurrency groups, `permissions: read-all`).

### Stale/triage/label automation

- `actions/stale` in 24 files: `flatbuffers/stale.yml` (6-month stale, 14-day close,
  `not-stale` exempt label, `operations-per-run: 500`), `gvisor/stale.yml`,
  `cadvisor/stale.yaml`, `osv-scanner/staleness.yml`.
- `actions/labeler` on `pull_request_target` (`flatbuffers/label.yml` — top-level
  `permissions: read-all`, job-scoped `pull-requests: write`), `gvisor/labeler.yml`,
  `comprehensive-rust/labeler.yml`.
- **AI agents doing triage (dogfooding ADK/Gemini)**: `adk-python/pr-triage.yml` runs an
  "ADK Pull Request Triaging Agent" every 6 hours (`pip install google-adk` →
  `python -m adk_pr_triaging_agent.main`), with siblings `issue-maintenance.yml` and
  `discussion_answering.yml`. Every ADK job is guarded with
  `if: github.repository == 'google/adk-python'` to prevent fork execution.
- `gvisor/issue_reviver.yml` (revives issues referenced by TODOs),
  `osv-scanner/title.yml` (conventional-commit PR title check).

### Docs publishing

`comprehensive-rust/publish.yml` (mdbook → Pages), `zx/docs.yml`,
`osv-scanner/docs-deploy.yml`, `magika/github-pages.yml`, `re2/pages.yml`,
`benchmark/doxygen.yml`.

## Structural patterns

**Action pinning — SHA pinning is common but *not* universal.** In the 66-file corpus:
154 SHA-pinned `uses:` vs. 273 tag-pinned. The split is clean per-repo, not per-file:

- *Fully SHA-pinned* (always with a trailing version comment, e.g.
  `actions/checkout@9c091bb2… # v7.0.0`): `guava`, `gson`, `go-github`, `guice`,
  `truth`, `yapf`, `pprof`, `benchmark`, `brotli`, `magika`, `libphonenumber`,
  `osv-scanner`, `closure-compiler`, `jsonnet`.
- *Tag-pinned only*: `gvisor`, `filament`, `flatbuffers`, `or-tools`, `oss-fuzz`,
  `adk-python`, `cadvisor`, `leveldb`, `re2`, `wire`, `go-cloud`, `comprehensive-rust`,
  `dagger`, `error-prone`.

SHA adoption correlates exactly with the repos that run Scorecard — it's a
scorecard-driven practice, backstopped by Dependabot (`dependabot.yml` in 109 repos) and
Renovate (15 repos; `osv-scanner` even has a `renovate-validator.yml`). The SLSA
generator is deliberately tag-pinned with a comment explaining the framework requires it.

**Least-privilege `permissions:`** — 54/66 files declare permissions somewhere; 42 at
top level. Three house styles:

1. `permissions: contents: read` top-level, then per-job elevation **with a comment
   justifying every line** — `guava/ci.yml`: `actions: write # for styfle/cancel-workflow-action…`
   (identical comment text across `guava`, `error-prone`, `truth` — clearly
   tool-generated, step-security style).
2. `permissions: read-all` (scorecard templates, `oss-fuzz`, `flatbuffers/label.yml`).
3. `permissions: {}` at top with job-scoped grants (`gson/cifuzz.yml`, `zx/zizmor.yml`).

The 12 files with no permissions at all skew older (`or-tools`, `filament`, `wire`,
`yapf`, `pprof`).

**Reusable workflows (`workflow_call`)** — 71 matching files org-wide. Flagship: the
`osv-scanner` → `osv-scanner-action` reusable pair consumed cross-repo;
`closure-compiler/run_tests.yaml` is callable; SLSA generators are consumed as reusable
workflows. Google both publishes and consumes reusable workflows, and **documents the
required caller `permissions:` in the workflow header**.

**Composite actions** — `dagger` (`./.github/actions/prechecks`, `bazel-build`),
`filament` (`mac-prereq`); `comprehensive-rust` unusually stores composite actions
*inside* `.github/workflows/` as directories alongside helper scripts — treating the
workflows dir as a mini CI toolkit.

**Concurrency** — 16 files; canonical form
`group: ${{ github.workflow }}-${{ github.ref }}` + `cancel-in-progress: true`
(`gvisor`, `filament`, `or-tools`, `osv-scanner`, `brotli`). `dagger` refines it:
`cancel-in-progress: ${{ github.ref != 'refs/heads/master' }}` (never cancel main
builds). Older Java repos still use the pre-`concurrency` idiom
(`styfle/cancel-workflow-action`).

**Timeouts** — rare: only 5/66 files set `timeout-minutes`. Not a Google norm.

**Token scoping** — beyond `permissions:`: `persist-credentials: false` (136 files),
dedicated PATs for cross-repo pushes (`gvisor/go.yml` with graceful fallback when the
secret is absent), bot-scoped tokens for agents (`ADK_TRIAGE_AGENT`).

**Triggers** (corpus histogram): `push` 40, `pull_request` 32, `workflow_dispatch` 19
(often a "manual test" escape hatch), `schedule` 16 (scorecard weekly, stale daily, OSV
weekly, `zx` runs its *tests* every 4 days, adk triage every 6h),
`branch_protection_rule` 6 (scorecard only), `release` 3, `workflow_call` 2,
`merge_group` in 42 files org-wide, `pull_request_target` only in labelers — consistent
with the org semgrep rule that flags it.

## Repo × feature table (sampled repos)

| Repo | Lang | CI matrix | Scorecard | CodeQL | Fuzzing | OSV/dep-review | Release autom. | Stale/label | SHA-pinned |
|---|---|---|---|---|---|---|---|---|---|
| guava | Java | JDK×POM | ✓ | – | – | – | snapshot deploy | – | ✓ |
| gson | Java | ✓ | ✓ | ✓ | CIFuzz | – | – | – | ✓ |
| error-prone / truth / guice / dagger / auto | Java | JDK incl. EA | – | – | – | – | maven release | – | mixed |
| googletest | C++ | – | – | – | – | – | – | – | – (Kokoro only) |
| leveldb | C++ | 3-axis | – | – | – | – | – | – | – |
| benchmark | C++ | 4-axis + sanitizers | ✓ | – | – | – | wheels | – | ✓ |
| or-tools | C++ | 36 workflows | – | – | – | – | – | – | – |
| flatbuffers | C++ | ✓ | – | – | – | – | SLSA3 release | stale+labeler | – |
| brotli | C/TS | build+wasm | ✓ | ✓ | fuzz.yml | – | BCR publish | – | ✓ |
| filament | C++ | per-OS + presubmit | – | – | – | – | npm/cocoapods | auto-close edits | – |
| gvisor | Go | smoke only | – | ✓ | – | – | – | stale+labeler+reviver | – (BuildKite real CI) |
| go-github | Go | ✓ | – | – | – | – | – | – | ✓ |
| osv-scanner | Go | ✓ | ✓ | ✓ | – | dogfoods itself | goreleaser+SLSA3 | stale, PR title | ✓ |
| cadvisor | Go | Go×config | – | – | – | – | container+binaries | stale | – |
| oss-fuzz | Shell/Py | infra tests | – | ✓ | ClusterFuzzLite | – | – | – | – |
| magika | Py/Rust/Go/JS | per-language | ✓ | ✓ | – | – | PyPI+npm + post-publish tests | issue-labeler | ✓ |
| adk-python | Python | ✓ | – | – | – | – | release-please multi-track | ADK triage agents | – |
| zx | JS | test+matrix | – | ✓ | – | osv.yml | npm+JSR | – | partial (zizmor) |
| comprehensive-rust | Rust | build+i18n | – | – | – | – | crates+Pages | labeler | – |
| libphonenumber | C++/Java | java+cpp | ✓ | ✓ | – | dep-review + OSV | – | – | ✓ |
| jsonnet | C++ | ✓ | – | – | – | – | gh-release+PyPI | – | ✓ |
| closure-compiler | Java | ✓ | ✓ | – | – | – | ✓ | – | ✓ |

## Distinctive / opinionated findings

1. **Google scans its own workflows as attack surface.**
   `google/.github` `action_scanning.yml` runs semgrep with org-custom rules against
   every repo's workflow files and uploads SARIF — including a policy rule that
   `pull_request_target` requires an explicit exception. Newer repos additionally run
   **zizmor** as a workflow linter. Workflows auditing workflows is the most distinctive
   pattern found.
2. **CLA is deliberately *not* an Actions concern.** Zero workflows reference googlebot —
   the CLA check is an external GitHub App. Actions is never trusted with CLA state.
3. **Dogfooding everywhere:** osv-scanner scans Google repos via its own published
   reusable workflow, oss-fuzz fuzzes its own infra with ClusterFuzzLite, and adk-python
   triages its own PRs/issues/discussions with Gemini-powered ADK agents on a 6-hour
   cron.
4. **google3 conventions leak out:** `presubmit`/`postsubmit` workflow names, Copybara PR
   auto-closers, `if: github.repository == 'google/…'` guards on every automation job,
   and Apache-2.0 license headers *inside YAML workflow files*.
5. **SHA pinning is real but scorecard-driven, not org-enforced:** Scorecard adopters pin
   everything to 40-char SHAs with `# vX.Y.Z` comments and justify each `permissions:`
   line in comments; repos without Scorecard happily use `@v4`. The one documented
   exception (`gson/cifuzz.yml`) links the upstream issue explaining why `@master` is
   unavoidable.
6. **Release engineering is bimodal:** classic repos use hand-rolled
   Maven/goreleaser/gh-release flows; the 2024+ generation standardizes on
   **release-please**, and supply-chain-conscious repos attach **SLSA level-3
   provenance** via the slsa-github-generator reusable workflow.

## What Google treats as core vs. supplementary

**Core (near-universal on active repos):** multi-axis build/test matrices on
`push` + `pull_request`; least-privilege `permissions:` blocks; Scorecard + CodeQL +
SARIF-to-dashboard on security-relevant repos; stale/labeler hygiene bots on
high-traffic repos; concurrency-cancel on PR pipelines; Dependabot for action updates.

**Supplementary (adopted per-team, unevenly):** SHA pinning (Scorecard adopters only),
harden-runner (mostly newer C++/security repos), timeouts (rare), SLSA provenance,
merge_group, zizmor, dependency-review, release-please (new repos only), AI triage
agents (adk family only).

**Explicitly *not* on Actions:** CLA enforcement (googlebot app), the heaviest CI for
infra-scale projects (gvisor → BuildKite, skia → LUCI, googletest → Kokoro), and
internal-sync mechanics beyond thin Copybara shims.

## Repos consulted

`guava`, `gson`, `error-prone`, `truth`, `guice`, `dagger`, `auto`, `googletest`,
`leveldb`, `benchmark`, `or-tools`, `flatbuffers`, `brotli`, `re2`, `filament`,
`gvisor`, `go-github`, `osv-scanner`, `cadvisor`, `wire`, `go-cloud`, `pprof`,
`oss-fuzz`, `yapf`, `python-fire`, `magika`, `adk-python`, `langextract`, `zx`,
`comprehensive-rust`, `libphonenumber`, `jsonnet`, `closure-compiler`,
`material-design-icons`, `skia`, `sanitizers`, `guetzli`, `sentencepiece`, plus the
org-level `google/.github` and `google/osv-scanner-action`.
