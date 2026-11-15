#!/usr/bin/env bash
# Applies the repository's GitHub security settings. Idempotent; safe to re-run.
#
# Most of these are only available for public repositories on the free plan, so run
# this right after making the repository public — and only after the rewritten
# history has been force-pushed, because the main ruleset blocks force pushes.
#
#   ./scripts/github-settings.sh            # apply
#   ./scripts/github-settings.sh --check    # show the current state only
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-ddavidgoraa/scribe}"
API="repos/$REPO"
ADMIN_ROLE=5 # built-in "Repository admin" role, allowed to bypass the rulesets below

# Prints a field, or "n/a" if GitHub doesn't offer it for this repository.
field() {
    local value
    value="$(gh api "$1" --jq "$2" 2>/dev/null)" || value="n/a"
    echo "${value:-n/a}"
}

check() {
    echo "Repository:        $(field "$API" '.visibility')"
    echo "Workflow token:    $(field "$API/actions/permissions/workflow" '.default_workflow_permissions')"
    echo "Fork PR approval:  $(field "$API/actions/permissions/fork-pr-contributor-approval" '.approval_policy')"
    echo "Secret scanning:   $(field "$API" '.security_and_analysis.secret_scanning.status // "n/a"')"
    echo "Push protection:   $(field "$API" '.security_and_analysis.secret_scanning_push_protection.status // "n/a"')"
    echo "Vuln. reporting:   $(field "$API/private-vulnerability-reporting" '.enabled')"
    echo "Rulesets:          $(field "$API/rulesets" 'map(.name) | join(", ")')"
}

if [[ "${1:-}" == "--check" ]]; then
    check
    exit 0
fi

if [[ "$(gh api "$API" --jq '.visibility')" != "public" ]]; then
    echo "The repository is not public yet; GitHub offers these settings to public repositories only." >&2
    echo "Make it public first (after force-pushing the rewritten history), then re-run." >&2
    exit 1
fi

echo "→ Actions: read-only GITHUB_TOKEN, no PR approvals by workflows"
gh api -X PUT "$API/actions/permissions/workflow" \
    -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false >/dev/null

echo "→ Actions: approval required for workflows from first-time contributors"
gh api -X PUT "$API/actions/permissions/fork-pr-contributor-approval" \
    -f approval_policy=first_time_contributors >/dev/null

echo "→ Secret scanning with push protection"
gh api -X PATCH "$API" --input - >/dev/null <<'JSON'
{"security_and_analysis": {
  "secret_scanning": {"status": "enabled"},
  "secret_scanning_push_protection": {"status": "enabled"}
}}
JSON

echo "→ Dependabot alerts and security updates"
gh api -X PUT "$API/vulnerability-alerts" >/dev/null
gh api -X PUT "$API/automated-security-fixes" >/dev/null

echo "→ Private vulnerability reporting"
gh api -X PUT "$API/private-vulnerability-reporting" >/dev/null

# Creates the ruleset, or updates it if one with the same name exists.
upsert_ruleset() {
    local name="$1" body="$2" id
    id="$(gh api "$API/rulesets" --jq ".[] | select(.name == \"$name\") | .id")"
    if [[ -n "$id" ]]; then
        gh api -X PUT "$API/rulesets/$id" --input - >/dev/null <<<"$body"
    else
        gh api -X POST "$API/rulesets" --input - >/dev/null <<<"$body"
    fi
}

echo "→ Ruleset: main only changes through pull requests with passing checks"
upsert_ruleset "Protect main" "$(cat <<JSON
{
  "name": "Protect main",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [{"actor_id": $ADMIN_ROLE, "actor_type": "RepositoryRole", "bypass_mode": "pull_request"}],
  "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "pull_request", "parameters": {
      "required_approving_review_count": 0,
      "dismiss_stale_reviews_on_push": true,
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "required_review_thread_resolution": false
    }},
    {"type": "required_status_checks", "parameters": {
      "strict_required_status_checks_policy": false,
      "required_status_checks": [{"context": "Tests"}, {"context": "Dependencies (cargo-deny)"}]
    }}
  ]
}
JSON
)"

echo "→ Ruleset: only admins create, move or delete v* release tags"
upsert_ruleset "Protect release tags" "$(cat <<JSON
{
  "name": "Protect release tags",
  "target": "tag",
  "enforcement": "active",
  "bypass_actors": [{"actor_id": $ADMIN_ROLE, "actor_type": "RepositoryRole", "bypass_mode": "always"}],
  "conditions": {"ref_name": {"include": ["refs/tags/v*"], "exclude": []}},
  "rules": [{"type": "creation"}, {"type": "update"}, {"type": "deletion"}]
}
JSON
)"

echo
check
