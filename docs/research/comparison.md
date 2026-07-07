# Cross-Org Comparison: Apple, Google, GitLab

> Synthesizes [`apple.md`](apple.md), [`google.md`](google.md), and
> [`gitlab.md`](gitlab.md) into where the three converge, where they diverge, and what
> that implies for the defaults chosen in this repo's reusable workflows. Read the
> per-org writeups for citations; this document only draws conclusions across them.

## Where all three converge

When three organizations with almost no overlap in tooling, language, and scale
independently arrive at the same practice, that's the strongest signal available that
the practice belongs in this library's **core** tier rather than its supplementary one.

**1. Least-privilege by default, escalated only where needed.** Apple declares
`permissions: contents: read` at the top of 54/57 sampled workflows and escalates
per-job. Google does the same in 42/66 files, with comments justifying every added
scope. GitLab enforces the equivalent through its fork-vs-canonical include
separation and AppSec-approval gates for sensitive changes. **This library's
response:** every reusable workflow here declares top-level `permissions: contents:
read` (or narrower) and documents the exact caller grant needed in its header
comment — never a blanket `write-all`.

**2. Reusable-workflow centralization over copy-paste.** Apple built two hubs
(`swiftlang/github-workflows`, and `apple/swift-nio` itself) that ~10+ sibling repos
call via `workflow_call`. Google publishes `google/osv-scanner-action` as a
cross-repo-consumed reusable workflow and documents the exact caller permissions in
its header. GitLab's CI/CD Components Catalog formalizes the same idea as a
versioned, semver-tagged, `spec.inputs`-typed package — `danger-review@2.1.0` is
included identically by 6+ independent GitLab projects. **This library's response:**
its entire structure — reusable `workflow_call` files with typed inputs, documented
required permissions, example callers — is this exact pattern, applied as the
library itself rather than as one org's internal tooling.

**3. Cancel superseded runs, but never the mainline.** Google uses
`concurrency: { group, cancel-in-progress: true }` broadly, with `dagger` refining it
to `cancel-in-progress: ${{ github.ref != 'refs/heads/master' }}`. GitLab sets
`interruptible: true` as an org-wide default with an explicit
`auto_cancel: on_new_commit: none` override on default-branch/tag/scheduled
pipelines. Apple adopts concurrency groups in its newer Swift-ecosystem and
`pkl`-generated workflows. All three independently distinguish "cancel my own
superseded feature-branch run" from "never cancel a protected-branch run." **This
library's response:** every CI-shaped reusable workflow's example caller sets
`concurrency` at the caller level (not baked into the reusable workflow itself, since
the callee doesn't know the caller's branch topology) — see the quick-start snippet
in the README for the recommended shape.

**4. Fork-safety guards on anything secret-bearing.** Apple:
`if: github.repository == 'apple/container'`. Google:
`if: github.repository == 'google/adk-python'` on every ADK automation job. GitLab:
`gitlab-runner` conditionally includes an entirely different file
(`_project_canonical.gitlab-ci.yml` vs. `_project_fork.gitlab-ci.yml`) based on
`$CI_PROJECT_PATH`, branching the include graph itself rather than just gating a
step. **This library's response:** `reusable-labeler.yml`'s header carries an
explicit security note about `pull_request_target` and forked-PR risk; any future
workflow that runs on `pull_request_target` should follow the same discipline.

**5. A human/process checkpoint before something ships.** Apple's `container`
publishes releases as **drafts**, requiring manual publish. Google's
`release-please` maintains a running release PR that a human merges rather than
auto-tagging on every push. GitLab's merge-train `pre-merge-checks` job requires the
pipeline be tier-3 (full suite) and recent before allowing merge. **This library's
response:** `reusable-github-release.yml` defaults `draft: true`, and
`reusable-release-please.yml` is the release-PR pattern, not an auto-tag-on-push
pattern.

**6. Security scanning delivered as a toggle-able template, not hand-rolled script.**
GitLab is the most mature/enforced form of this — SAST/DAST/Dependency-Scanning/
Secret-Detection are one-line `include: template:` references toggled by CI
variables, mandated org-wide. Google is broad-but-voluntary: Scorecard (39 files),
CodeQL (41 files), harden-runner (64 files) — real adoption, but no org-wide mandate,
and repos without Scorecard happily skip SHA-pinning too. Apple is the least
consistent of the three: CodeQL only where pkl/servicetalk chose it, no Scorecard
found anywhere in the sample. **This library's response:** the core tier
(`reusable-codeql.yml`, `reusable-dependency-review.yml`, `reusable-scorecard.yml`,
`reusable-zizmor.yml`) treats security scanning as GitLab treats it — a default you
opt out of, not an afterthought you opt into — while still exposing enough
`workflow_call` inputs that a caller can tune severity thresholds per repo.

**7. Dogfooding your own tooling in your own CI.** Google's `osv-scanner` scans
Google's own repos via its own published reusable workflow; `oss-fuzz` fuzzes its own
infrastructure with ClusterFuzzLite; `adk-python` triages its own issues with a
Gemini-powered agent. GitLab's `danger-review` bot output (labels) feeds back into
its own pipeline's behavior, and it uses its own Duo AI product to pick which system
tests to run. Apple's `pkl` repos generate their own GitHub Actions YAML using Pkl,
the config language the repo exists to promote. **This library's response:**
`self-check.yml` runs `reusable-zizmor.yml` against this repo's own workflow files —
the same instinct, applied at a much smaller scale.

## Where they diverge

**SHA-pinning discipline is a GitHub Actions-specific concern with no GitLab
analog.** Google's SHA-pinning (154 SHA-pinned vs. 273 tag-pinned refs in the
sampled corpus) correlates almost exactly with Scorecard adoption — it's a defense
against a compromised or force-pushed *third-party* action tag. Apple pins ~75% of
its 651 sampled `uses:` references the same way. GitLab's `include:` mechanism rarely
reaches outside the GitLab organization itself (`project:` includes reference other
GitLab-org projects; `component:` includes reference the GitLab-run Components
Catalog) — the supply-chain threat model that makes SHA-pinning valuable in GHA
barely applies, because GitLab isn't routing its critical CI logic through
externally-maintained third-party code the way GHA consumers route through
`actions/checkout` or `ossf/scorecard-action`. **Implication:** this library's
SHA-pinning discipline (every third-party `uses:`, version-commented) is a
GHA-specific practice worth keeping strict, precisely because GHA's action ecosystem
*is* the supply-chain surface GitLab's architecture largely avoids.

**GitLab's test-execution sophistication has no GHA-native equivalent.** GitLab's
predictive test selection (Crystalball dynamic mappings, a static fallback map, and
now Duo-AI-based system-test selection) plus its three-tier MR-approval-driven test
scope (tier-1/2/3) go considerably further than anything in the Apple or Google
samples — neither org's public CI narrows *which tests run* based on either changed
files or review state to this degree. **Implication:** this is flagged as a known
gap, not something this library attempts to replicate. A GHA-native equivalent would
require a custom action calling the GitHub API to inspect review state and a
change-impact-mapping tool (Nx/Turborepo-style), which is a bigger investment than a
general-purpose reusable-workflow library should assume every consumer wants.

**Where the heaviest CI actually runs differs by org, for different reasons.** Apple
splits sharply: maintained products get heavy Actions-based CI, but the entire
`ml-*` research-code catalog ships with zero automation — a product-maturity
distinction, not a technical one. Google splits by *how internally load-bearing* the
project is: `gvisor`'s real pipeline is BuildKite, `skia` is a LUCI/Gerrit mirror,
`googletest` runs on internal Kokoro — Google trusts internal infrastructure most for
the projects deepest inside its own build system, and uses GitHub Actions as the
public-facing/community-facing CI layer. GitLab has no equivalent internal-only
shadow system for its flagship product, because GitLab CI/CD is the thing it's
dogfooding — there's nowhere else for `gitlab-org/gitlab`'s pipeline to live.
**Implication:** a repo adopting this library should expect GitHub Actions to be
sufficient for the community-facing and release-gating concerns this library covers,
but shouldn't assume it's the *only* CI system a sufficiently large or
infrastructure-heavy project might still run alongside it.

**Centralization maturity for conditional triggering varies widely.** GitLab
centralizes 361 `changes:` path-filter usages into ~15 shared pattern anchors
(`&backend-patterns`, `&frontend-patterns`, etc.) referenced everywhere — one
canonical definition of "what counts as a backend change." Apple's `servicetalk` uses
aggressive `paths-ignore` lists but doesn't centralize them across repos (each repo
defines its own). Google's sample showed path-based skipping present but not
emphasized as a distinct, shared-library concern the way GitLab treats it.
**Implication:** if this library grows path-filtered variants of its CI workflows, the
GitLab pattern — one shared set of named path-glob definitions, not one per
consuming repo — is the one to imitate, even though nothing here implements it yet.

## What this implies for this library's defaults

The three-way convergence points (permissions, reusable-workflow centralization,
cancel-superseded-not-mainline concurrency, fork-safety guards, draft/gated
releases, toggle-able security scanning, dogfooding) are exactly the properties
encoded into every `reusable-*.yml` file in `.github/workflows/` — see each file's
header comment for the specific upstream pattern it's modeled on. The divergence
points mark where this library **doesn't** try to replicate a foreign architecture
(GitLab's dynamic child pipelines, cross-pipeline `needs:`, or predictive test
selection have no clean GHA translation and aren't attempted here) rather than where
the research was inconclusive — the gaps are structural, not gaps in the research.
