#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Idempotently configure a GitHub repository for this workflow-library adoption model.

Usage:
  scripts/bootstrap-repo.sh [options]

Options:
  --repo OWNER/REPO            Target repository (default: inferred from git remote).
  --main-branch NAME           Protected default branch (default: main).
  --preview-env NAME           Preview environment name (default: preview).
  --live-env NAME              Live environment name (default: live).
  --live-reviewer USERNAME     GitHub user required to approve live deployments.
  --live-wait-minutes N        Wait timer for live deployments (default: 0).
  --required-check NAME        Required status check context on main (repeatable).
  --required-reviews N         Required PR approvals on main (default: 1).
  --no-create-env-branches     Skip creating preview/live branches.
  --dry-run                    Print API actions without mutating repository settings.
  --help                       Show this help text.

Examples:
  scripts/bootstrap-repo.sh --repo chrispivonka/github-actions
  scripts/bootstrap-repo.sh \
    --repo acme/service \
    --live-reviewer octocat \
    --required-check "zizmor / Audit workflows with zizmor" \
    --required-check "actionlint / Lint workflow YAML with actionlint"
EOF
}

require_bin() {
  local bin="$1"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "Missing required binary: $bin" >&2
    exit 1
  fi
}

REPO=""
MAIN_BRANCH="main"
PREVIEW_ENV="preview"
LIVE_ENV="live"
LIVE_REVIEWER=""
LIVE_WAIT_MINUTES=0
REQUIRED_REVIEWS=1
CREATE_ENV_BRANCHES=true
DRY_RUN=false
REQUIRED_CHECKS=(
  "Quality gate / Gate"
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="$2"
      shift 2
      ;;
    --main-branch)
      MAIN_BRANCH="$2"
      shift 2
      ;;
    --preview-env)
      PREVIEW_ENV="$2"
      shift 2
      ;;
    --live-env)
      LIVE_ENV="$2"
      shift 2
      ;;
    --live-reviewer)
      LIVE_REVIEWER="$2"
      shift 2
      ;;
    --live-wait-minutes)
      LIVE_WAIT_MINUTES="$2"
      shift 2
      ;;
    --required-check)
      REQUIRED_CHECKS+=("$2")
      shift 2
      ;;
    --required-reviews)
      REQUIRED_REVIEWS="$2"
      shift 2
      ;;
    --no-create-env-branches)
      CREATE_ENV_BRANCHES=false
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_bin gh
require_bin jq

if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi

api_call() {
  local method="$1"
  local endpoint="$2"
  local payload="${3:-}"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] $method $endpoint"
    if [[ -n "$payload" ]]; then
      echo "$payload" | jq .
    fi
    return 0
  fi

  if [[ -n "$payload" ]]; then
    gh api --method "$method" "$endpoint" --input - <<<"$payload" >/dev/null
  else
    gh api --method "$method" "$endpoint" >/dev/null
  fi
}

api_try_call() {
  local method="$1"
  local endpoint="$2"
  local payload="${3:-}"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] $method $endpoint (best-effort)"
    if [[ -n "$payload" ]]; then
      echo "$payload" | jq .
    fi
    return 0
  fi

  if [[ -n "$payload" ]]; then
    gh api --silent --method "$method" "$endpoint" --input - <<<"$payload" >/dev/null || true
  else
    gh api --silent --method "$method" "$endpoint" >/dev/null || true
  fi
}

echo "Configuring repository: $REPO"

repo_payload="$(
  jq -n \
    '{allow_auto_merge: true, delete_branch_on_merge: true, allow_merge_commit: false, allow_rebase_merge: false, allow_squash_merge: true}'
)"
api_call PATCH "repos/$REPO" "$repo_payload"
echo "✓ Repository merge settings configured"

workflow_perm_payload='{"default_workflow_permissions":"write","can_approve_pull_request_reviews":false}'
api_call PUT "repos/$REPO/actions/permissions/workflow" "$workflow_perm_payload"
echo "✓ Actions workflow token permissions configured (read/write)"

checks_json="$(
  printf '%s\n' "${REQUIRED_CHECKS[@]}" | awk 'NF > 0' | jq -R . | jq -s .
)"
protection_payload="$(
  jq -n \
    --argjson contexts "$checks_json" \
    --argjson required_reviews "$REQUIRED_REVIEWS" \
    '{
      required_status_checks: { strict: true, contexts: $contexts },
      enforce_admins: true,
      required_pull_request_reviews: {
        dismiss_stale_reviews: true,
        require_code_owner_reviews: false,
        required_approving_review_count: $required_reviews,
        require_last_push_approval: true
      },
      restrictions: null,
      required_linear_history: true,
      allow_force_pushes: false,
      allow_deletions: false,
      block_creations: false,
      required_conversation_resolution: true,
      lock_branch: false,
      allow_fork_syncing: true
    }'
)"
api_call PUT "repos/$REPO/branches/$MAIN_BRANCH/protection" "$protection_payload"
api_try_call POST "repos/$REPO/branches/$MAIN_BRANCH/protection/required_signatures"
echo "✓ Branch protection configured for $MAIN_BRANCH"

reviewers_json='[]'
if [[ -n "$LIVE_REVIEWER" ]]; then
  reviewer_id="$(gh api "users/$LIVE_REVIEWER" --jq .id)"
  reviewers_json="$(jq -n --argjson id "$reviewer_id" '[{type:"User", id:$id}]')"
fi

preview_env_payload="$(
  jq -n \
    '{wait_timer: 0, reviewers: [], deployment_branch_policy: {protected_branches: true, custom_branch_policies: false}}'
)"
api_call PUT "repos/$REPO/environments/$PREVIEW_ENV" "$preview_env_payload"
echo "✓ Environment ensured: $PREVIEW_ENV"

live_env_payload="$(
  jq -n \
    --argjson wait_timer "$LIVE_WAIT_MINUTES" \
    --argjson reviewers "$reviewers_json" \
    '{wait_timer: $wait_timer, reviewers: $reviewers, deployment_branch_policy: {protected_branches: true, custom_branch_policies: false}}'
)"
api_call PUT "repos/$REPO/environments/$LIVE_ENV" "$live_env_payload"
echo "✓ Environment ensured: $LIVE_ENV"

if [[ "$CREATE_ENV_BRANCHES" == "true" ]]; then
  main_sha="$(gh api "repos/$REPO/git/ref/heads/$MAIN_BRANCH" --jq .object.sha)"
  for branch in "$PREVIEW_ENV" "$LIVE_ENV"; do
    if gh api "repos/$REPO/git/ref/heads/$branch" >/dev/null 2>&1; then
      echo "✓ Branch exists: $branch"
      continue
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[dry-run] create branch $branch from $MAIN_BRANCH ($main_sha)"
    else
      gh api --method POST "repos/$REPO/git/refs" \
        -f ref="refs/heads/$branch" \
        -f sha="$main_sha" >/dev/null
    fi
    echo "✓ Branch ensured: $branch"
  done
fi

echo
echo "Bootstrap complete for $REPO"
echo "Recommended next checks:"
echo "  1) gh api repos/$REPO/branches/$MAIN_BRANCH/protection"
echo "  2) gh api repos/$REPO/environments/$PREVIEW_ENV"
echo "  3) gh api repos/$REPO/environments/$LIVE_ENV"
