# How GitLab Structures Its Own CI/CD

> Research conducted July 2026 against the live `.gitlab-ci.yml` configuration trees of
> `gitlab-org/gitlab` (the monolith — ~4,400 lines of CI config across the entry file
> plus `.gitlab/ci/rules.gitlab-ci.yml`), plus the pipelines of `gitlab-runner`,
> `gitlab-shell`, `gitaly`, `gitlab-pages`, `cli`, `gitlab-vscode-extension`,
> `omnibus-gitlab`, and `charts/gitlab`, fetched via the public GitLab API, plus
> GitLab's own CI/CD docs and the `danger-review` CI/CD component source. GitLab CI
> concepts are translated to GitHub Actions equivalents throughout, since the point of
> this research is what's transferable to this repo's workflow library.

## Org-wide summary

GitLab dogfoods its own product at extreme scale: the `gitlab-org/gitlab` pipeline is
not one file but a **mega-pipeline assembled from ~40 included fragments**
(`.gitlab/ci/*.gitlab-ci.yml`) totaling several thousand lines, run against every merge
request. Unlike Apple/Google's GitHub Actions usage (org-level reusable-workflow
libraries), GitLab's reuse mechanisms are **three-tiered**: (1) plain `include:` of
local/remote/project files, (2) `Jobs/*.gitlab-ci.yml` **CI/CD templates** shipped
inside the `gitlab` codebase itself (Auto DevOps, SAST, Dependency-Scanning, etc.), and
(3) the newer **CI/CD Components Catalog** (semver-versioned, input-parameterized
building blocks, GA since GitLab 17.0) — the closest analog to a GitHub Actions
reusable-workflow/composite-action library. Every satellite project studied
(`gitlab-runner`, `gitaly`, `gitlab-shell`, `cli`, `gitlab-vscode-extension`,
`charts/gitlab`) consumes the same `danger-review` **component** and the same
`Jobs/SAST`, `Jobs/Dependency-Scanning`, `Jobs/Secret-Detection` **templates** — a
genuinely enforced org-wide standard, not just convention.

The monolith's pipeline is dominated by **predictive/tiered testing** (run only the
tests likely to fail, tiered by MR approval state), **fail-fast cancellation**, heavy
**caching with pull/pull-push job separation**, and **dynamically-generated child
pipelines** for E2E — patterns considerably more elaborate than anything commonly seen
in GitHub Actions.

## Mega-pipeline structure

### Top-level file: `gitlab-org/gitlab` `.gitlab-ci.yml`

- 19 `stages:` (`sync, preflight, prepare, build-images, release-environments,
  fixtures, lint, test-frontend, test, post-test, review, qa, post-qa, pre-merge,
  pages, notify, benchmark, ai-gateway`) — far more granular than a typical GHA
  `jobs:` DAG, because GitLab stages are a **global sequential barrier** (all jobs in
  stage N must finish/allow_failure before stage N+1 starts), which the project works
  around heavily with `needs:` to get DAG-like parallelism across stages.
- `default:` sets `interruptible: true` for **all** jobs org-wide (superseding GHA's
  per-workflow `concurrency: cancel-in-progress`).
- YAML anchors (`&default-ruby-variables`, `&if-merge-request-security-canonical-sync`,
  etc.) are used pervasively as **named, reusable rule/variable snippets** merged via
  `<<:` — a lower-tech version of GHA's `workflow_call` inputs, but resolved at
  YAML-parse time rather than runtime.
- `workflow:` (lines 59–238) is a single ordered list of ~25 `rules:` entries that both
  **gates whether a pipeline runs at all** and **sets pipeline-wide variables** (e.g.
  `PIPELINE_NAME`, `RUBY_VERSION`, `auto_cancel: on_new_commit: none` for
  default-branch/tag pipelines). This is the direct equivalent of combining GHA's
  `on:` triggers + path/branch filters + a manual "should this run at all" gate job.
- `include:` mixes `local:` (glob `.gitlab/ci/*.gitlab-ci.yml`), `remote:` (a raw URL
  to another public repo's YAML), and per-include `rules:` that decide whether that
  fragment is even loaded.

### `.gitlab/ci/rules.gitlab-ci.yml` — a 4,043-line central rules library

This single file is the source of truth for all conditional logic in the monolith,
and is the single most distinctive structural artifact found:

- Hundreds of named `if:` anchors (`.if-merge-request`, `.if-default-branch-refs`,
  `.if-merge-request-labels-run-all-rspec`, `.if-fork-merge-request`,
  `.if-merge-request-tier-1/2/3`, etc.) — essentially a **DSL of predicate fragments**
  referenced everywhere via `<<: *anchor` or `!reference [.name, rules]`.
- `changes:` path-filter arrays appear **361 times**, built from large reusable
  anchors like `&backend-patterns`, `&core-backend-patterns`, `&ci-patterns`,
  `&db-patterns`, `&frontend-patterns` (rules.yml:593, 1095, 310) — each a curated
  glob list (e.g. `&backend-patterns` includes
  `app/{channels,controllers,models,...}/**/*`, `Gemfile{,.lock}`,
  `.gitlab/ci/**/*`). This is functionally identical to GitHub's
  `paths:`/`dorny/paths-filter`, but centralized into one canonical library instead
  of duplicated per workflow.
- A three-tier MR system (confirmed both in code and in GitLab's dev docs):
  **tier-1** (no approvals yet, predictive-only tests), **tier-2** (partial
  approval), **tier-3** (fully approved, full suite) — driven by `pipeline::tier-N`
  MR labels and rule anchors `.if-merge-request-tier-1/2/3`.

### `extends:` / DAG `needs:`

- `extends:` composes jobs from multiple traits (e.g. `static-analysis` extends
  `.static-analysis-base`, `.static-analysis-cache`,
  `.static-analysis:rules:static-analysis`, `.use-pg17`).
- `needs:` breaks the strict stage-barrier model to build a real DAG:
  `update-tests-metadata` (test-metadata.yml:28) needs specific artifact-collector
  jobs by name with `optional: true`, so the pipeline continues even if upstream jobs
  were skipped by rules. Cache-warm jobs (`cache:ruby-gems`, `cache:node-modules`) are
  referenced via `needs: [{job: cache:ruby-gems, optional: true}]` rather than
  `stage:` ordering.
- **`!reference [...]`** (a YAML custom tag) reuses a *specific key* from another
  job/anchor (e.g. `!reference [.lint-base, needs]`) — more granular than `extends:`,
  closer to importing a single field from shared config than a whole job.

### Child/downstream pipelines

- `qa.gitlab-ci.yml`'s `e2e-test-pipeline-generate` job (setup.yml:289) runs a rake
  task that *writes a pipeline YAML file to disk as a job artifact*
  (`qa/tmp/test-on-omnibus-pipeline.yml`), and downstream jobs trigger it via
  `trigger: { strategy: depend, include: [{ artifact: $DYNAMIC_PIPELINE_YML, job:
  e2e-test-pipeline-generate }] }`. This is **fully dynamic pipeline generation at
  runtime** — a job's own script output becomes the next pipeline's definition. GitHub
  Actions has no equivalent (workflow files must exist in the repo at trigger time).
- `charts/gitlab`'s `.review_template` (proj-charts-gitlab.yml:258) uses
  **cross-pipeline `needs:`**: `needs: [{pipeline: $PARENT_PIPELINE_ID, job:
  pin_image_versions}]` — a child pipeline depending on a specific job in its parent.
  No GHA equivalent (a called reusable workflow can't reach back into the caller's
  job graph).
- `strategy: depend` makes the parent pipeline's status depend on the child's,
  similar in spirit to a GHA reusable-workflow call blocking on its outcome.

## Reusable-workflow equivalents

| GitLab mechanism | Where observed | GHA analog |
|---|---|---|
| `include: local:` (glob) | `.gitlab-ci.yml` → `.gitlab/ci/*.gitlab-ci.yml` | Splitting one workflow into multiple files — GHA has no true equivalent (`workflow_call` is closest but per-file, not glob) |
| `include: remote:` | a raw URL to `frontend/untamper-my-lockfile` | Manually curling/checking out a workflow file — GHA can't `include:` a remote raw file directly |
| `include: project:` | `cli`, `gitlab-runner` both include an `oidc-modules` project's `templates/gcp_auth.yaml` for cloud OIDC auth | `uses: org/repo/.github/workflows/x.yml@ref` (`workflow_call`) |
| `include: template:` | `Jobs/SAST.gitlab-ci.yml`, `Jobs/Dependency-Scanning.gitlab-ci.yml`, `Code-Quality.gitlab-ci.yml` — shipped inside `gitlab-org/gitlab` at `lib/gitlab/ci/templates/` (60+ language templates) | A GitHub Actions "starter workflow" template gallery |
| `include: component:` (CI/CD Components Catalog) | Every satellite project studied includes `components/danger-review/danger-review@2.1.0`; `cli`/`gitlab-shell` also include `components/code-intelligence/golang-code-intel@v0.4.1` | A versioned, input-parameterized reusable workflow or composite action published for org-wide reuse |
| Auto DevOps | `lib/gitlab/ci/templates/Auto-DevOps.gitlab-ci.yml` — full build→test→review→dast→staging→canary→production, auto-detected via `workflow: rules: - exists: [Dockerfile, go.mod, ...]` | No single GHA equivalent — GHA has no auto-detection-by-file-existence trigger |

**CI/CD Component anatomy** (from `gitlab-org/components/danger-review`,
`templates/danger-review/template.yml`): a component is a YAML with a `spec.inputs:`
block (typed, defaulted parameters like `job_image`, `job_stage`, `dry_run: boolean`)
and a body using `$[[ inputs.x ]]` interpolation — structurally identical to a GHA
reusable workflow's `on.workflow_call.inputs`, but distributed via a
**project-as-package** model with semver tags (`@2.1.0`) and discoverability through
the public CI/CD Catalog. GitHub Marketplace solves discoverability for whole
actions, but has no first-party analog to a *pipeline-fragment* catalog.

## What GitLab treats as core vs. supplementary

**Core (always present, blocking, tightly wired into the rules library):**

- **Predictive/tiered RSpec + Jest**: `detect-tests` (setup.yml:158) computes a
  changed-files → matching-tests mapping using Crystalball dynamic mappings, a static
  `tests.yml` fallback, and (new, distinctive) **AI-based test selection via
  `@gitlab/duo-cli`** in `detect-system-tests-duo` (setup.yml:188) — GitLab dogfoods
  its own Duo AI agent to pick which system tests to run.
- **Fail-fast + early cancellation**: `rspec fail-fast` runs only the
  predictively-matched tests first; `fail-pipeline-early` cancels the rest of the
  pipeline via the API if that subset fails.
- **Danger review + `Dangerfile`**: every satellite project wires the
  `danger-review` component; `gitlab-org/gitlab` gates its `set-pipeline-name` job on
  `needs: [{job: danger-review, optional: true}]` "to fetch labels it adds" — bot
  output (MR labels) feeds back into pipeline behavior.
- **rubocop/eslint**: `static-analysis` job plus dedicated `eslint`,
  `eslint-changed-files`, `eslint-todo-no-apollo-mock` jobs, each with its own
  `rubocop-cache`/`rubocop-cache-push` split.
- **Coverage**: RSpec + Jest coverage merged with E2E per-test coverage, streamed
  into ClickHouse — coverage isn't just a gate, it's a queryable analytics dataset
  feeding predictive test selection.
- **Flaky-test handling**: `RETRY_FAILED_TESTS_IN_NEW_PROCESS: "true"`, a dedicated
  flaky-test report path, and a `FAST_QUARANTINE` flag that skips known-flaky tests
  under investigation.
- **Merge trains + pre-merge gate**: `pre-merge-checks` enforces that the merge-train
  pipeline is tier-3 (full suite) and recent before allowing merge.
- **Security scanning, externalized**: `gitlab-org/gitlab` is the upstream *source*
  of the SAST/DAST templates; every other GitLab project includes
  `Jobs/SAST(.latest).gitlab-ci.yml`, `Security/Dependency-Scanning.gitlab-ci.yml`,
  `Security/Secret-Detection.gitlab-ci.yml` as boilerplate, toggled by
  `SAST_DISABLED`/`DAST_DISABLED`/`SAST_EXCLUDED_ANALYZERS` variables.

**Supplementary/opt-in (scheduled, label-gated, or `allow_failure: true`):**

- Review apps — absent from the `gitlab-org/gitlab` monolith itself (dropped for
  cost; E2E against GDK/CNG/Omnibus child pipelines substitutes) but fully
  implemented in `charts/gitlab` (`.review_template`, a real Kubernetes
  deploy-per-MR) and in Auto DevOps.
- Weekly/scheduled pipelines run a wider, non-default test surface (e.g.
  `FAST_QUARANTINE: "false"` only on weekly runs).
- Benchmark stage, AI-gateway stage — niche, isolated stages gated by dedicated rule
  files.
- Bundle-size-review and similar non-blocking visibility jobs
  (`allow_failure: true`) surface debt without gating merges.

## Security scanning wiring

- **Templates, not custom scripts**: `Jobs/SAST.gitlab-ci.yml`,
  `Jobs/Dependency-Scanning.(latest/v2).gitlab-ci.yml`,
  `Jobs/Secret-Detection.(latest).gitlab-ci.yml`, `Jobs/Container-Scanning.gitlab-ci.yml`,
  `Jobs/SAST-IaC.gitlab-ci.yml`, `Jobs/DAST-Default-Branch-Deploy.gitlab-ci.yml` all
  live under `lib/gitlab/ci/templates/Jobs/` in `gitlab-org/gitlab` and are consumed
  downstream via a single `include: - template:` line — no copy-paste of scanner
  config anywhere.
- Toggled off per-analyzer via CI variables rather than editing the pipeline — a
  "disable by variable" pattern that keeps the include stable.
- Cloud auth for scanners/deploys is itself a reusable include: `gitlab-runner` and
  `cli` both pull an `oidc-modules` project's `templates/gcp_auth.yaml` — OIDC
  federation packaged as an includable template, directly analogous to a shared GHA
  "configure-aws-credentials"/"auth-to-gcp" reusable workflow.

## Efficiency patterns

- **`interruptible: true` by default**, with a single explicit opt-out job
  (`dont-interrupt-me`, `interruptible: false`) that exists purely to *prevent*
  cancellation when needed — the inverse of the usual pattern.
- **Split cache-warming jobs**: `cache:ruby-gems`, `cache:node-modules`, etc. run
  once per pipeline with `policy: pull-push`; every consumer job declares the same
  cache key with `policy: pull` only, avoiding N jobs each redundantly writing the
  same cache. Cache keys are content-hashed and prefixed with toolchain versions —
  comparable to `actions/cache`'s `hashFiles()` pattern, but centralized into ~20
  named cache anchors reused everywhere.
- **361 `rules:changes` path filters** built from ~15 large reusable pattern anchors
  — GitLab centralizes the glob lists into one library file and merges rules via
  anchor reference, unlike most GHA repos where path filters are duplicated per
  workflow.
- **Predictive test selection** (Crystalball + Duo AI) reduces the RSpec/Jest surface
  run per MR far below path-filtering alone — no common GHA equivalent; the closest
  real-world analogs are Nx/Turborepo affected-project graphs.
- **`auto_cancel: on_new_commit: none`** is set specifically on
  default-branch/tag/scheduled pipeline rules to *prevent* interrupting a
  production-branch pipeline even though `interruptible: true` is the job default —
  a deliberate distinction between "cancel my own superseded MR run" and "never
  cancel a mainline run."
- **Retry taxonomy**: `.default-retry` retries only on specific *infra* failure
  reasons (`api_failure`, `runner_system_failure`, `stuck_or_timeout_failure`, a
  custom exit code for low disk space) — not blanket retries, which would mask real
  flakiness.

## Governance / hygiene

- **`gitlab-org/quality/triage-ops`** is GitLab's stale-bot-and-then-some: a
  reactive webhook app for real-time label/community-contribution management via
  `@gitlab-bot`, plus scheduled GitLab CI/CD pipeline "policies" for periodic
  hygiene (stale issue/MR labeling, SLO monitoring, triage reports), built on the
  `gitlab-triage` gem — architecturally a combination of `actions/stale`, a
  webhook-driven bot, and a scheduled reporting workflow, unified under one project.
- **Fork vs. canonical separation of includes**: `gitlab-runner` conditionally
  includes `_project_canonical.gitlab-ci.yml` vs. `_project_fork.gitlab-ci.yml`
  based on `$CI_PROJECT_PATH` — a structural safeguard so fork pipelines never get
  secrets/jobs meant only for the canonical project, enforced by branching the
  *include graph itself* rather than just gating steps (conceptually parallel to
  GitHub's `pull_request` vs. `pull_request_target` distinction).

## Lessons transferable to GitHub Actions

**Maps cleanly — already reflected in this library or worth adopting:**

- `rules:changes` + centralized pattern anchors → GHA `paths:` /
  `dorny/paths-filter`, but GitLab's discipline of **one shared library of named
  path-glob sets** reused across dozens of jobs (rather than inlined per-workflow)
  is worth copying literally for any repo defining more than a couple of CI
  workflows.
- `interruptible: true` default + `auto_cancel: on_new_commit: none` override → GHA
  `concurrency: { group, cancel-in-progress: true }` per workflow, with an explicit
  exception for protected branches — directly portable, and already this library's
  default recommendation.
- CI/CD Components Catalog (spec/inputs, semver) → GHA reusable workflows
  (`workflow_call` + `inputs:`), tagged and published to a shared repo. GitLab's
  `danger-review@2.1.0` pattern — one versioned component included identically by
  6+ independent projects — is exactly the target shape of this repo's library.
- Security scanning templates as one-line includes, toggled by variables → this
  repo's `reusable-codeql.yml` / `reusable-dependency-review.yml` /
  `reusable-scorecard.yml`, called via `workflow_call` and toggled by caller inputs
  instead of editing the callee.
- Split cache-warm job + downstream pull-only consumers → `actions/cache` with a
  dedicated "prime cache" job that other jobs `needs:` and then hit as a
  cache-restore (not re-save) — avoids redundant cache writes across a matrix.
- Merge-train pre-merge gate (tier-3, recency check) → GHA's `merge_group` trigger
  (merge queue) combined with a required check validating the merge-queue run
  reflects the latest base branch.
- Retry-by-failure-reason → a composite action wrapping steps with retry only on
  specific exit codes/error patterns, rather than blanket `continue-on-error`.

**No clean GHA equivalent (a real capability gap, not just a missing convention):**

- **Dynamically generated child pipelines** (a job's script output becomes the next
  stage's pipeline definition). GHA workflows must exist as committed files at
  trigger time; the closest workaround is a matrix built from a job's JSON output
  (`fromJson()`), which is materially less flexible.
- **Cross-pipeline `needs: pipeline: $ID`** (a child pipeline job depending on a
  specific job in its *parent*). GHA reusable workflows are one-directional
  (caller → callee only).
- **Predictive/AI-driven test selection** (Crystalball + Duo AI system-test
  selection) — GHA has no first-party test-impact-analysis primitive; this would
  need a custom action or third-party tool (Nx affected, Turborepo, or a bespoke
  mapping script).
- **Named rule-anchor DSL merged via `<<:`/`!reference`** — YAML anchors give
  GitLab a form of partial job inheritance (merge just the `rules:` key, or just
  `before_script:`) that GHA's `workflow_call`/composite actions can't replicate
  directly.
- **Tiered pipelines driven by MR approval state** (tier-1/2/3 via labels) — GHA has
  no native concept of "this PR has N approvals, so run more tests"; it would
  require a custom action calling the GitHub API to check review state.
- **CI/CD Catalog discoverability** — GitHub Marketplace covers whole actions, but
  there's no first-party equivalent to a catalog specifically for pipeline
  *fragments*/templates the way GitLab's Components Catalog is scoped.

## Key files consulted

`gitlab-org/gitlab`: `.gitlab-ci.yml`, `.gitlab/ci/rules.gitlab-ci.yml` (4,043
lines), `.gitlab/ci/global.gitlab-ci.yml`, `.gitlab/ci/caching.gitlab-ci.yml`,
`.gitlab/ci/rails.gitlab-ci.yml`, `.gitlab/ci/qa.gitlab-ci.yml`,
`.gitlab/ci/setup.gitlab-ci.yml`, `.gitlab/ci/coverage.gitlab-ci.yml`,
`.gitlab/ci/static-analysis.gitlab-ci.yml`, `.gitlab/ci/test-metadata.gitlab-ci.yml`,
`.gitlab/ci/notify.gitlab-ci.yml`, `.gitlab/ci/pre-merge.gitlab-ci.yml`,
`.gitlab/ci/release-environments.gitlab-ci.yml`,
`lib/gitlab/ci/templates/Auto-DevOps.gitlab-ci.yml`,
`lib/gitlab/ci/templates/Jobs/{SAST,Dependency-Scanning,Secret-Detection,Container-Scanning,Code-Quality}*.gitlab-ci.yml`;
`gitlab-org/gitlab-runner`, `gitlab-org/gitlab-shell`, `gitlab-org/gitaly`,
`gitlab-org/gitlab-pages`, `gitlab-org/cli`, `gitlab-org/gitlab-vscode-extension`,
`gitlab-org/omnibus-gitlab`, `gitlab-org/charts/gitlab` (root `.gitlab-ci.yml` of
each); `gitlab-org/components/danger-review`
(`templates/danger-review/template.yml`); `gitlab-org/quality/triage-ops`
(`README.md`); GitLab docs `docs.gitlab.com/ee/ci/components/` and
`docs.gitlab.com/ee/development/pipelines/`.
