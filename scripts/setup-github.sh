#!/usr/bin/env bash
# GitHub controls (Build Steps section 3, steps 5 to 8): protect main, keep every candidate branch as evidence, then
# check that no GitHub App can bypass either ruleset.
#   scripts/setup-github.sh <owner>/<repo>
# Run it only once the service under test's seeded commits are on main: from then on main needs pull requests.
# Private repos: rulesets need GitHub Team (or Pro for a personal account), a plan feature, not a paid security
# add-on. On GitHub Free they aren't available; the MCP server's own branch and path enforcement is then the only
# control on the Engineer's writes (the agents never see the App credentials). Record that residual risk.
# Needs: gh signed in as a repo admin.
set -euo pipefail
REPO="${1:?usage: setup-github.sh <owner>/<repo>}"
have() { gh api "repos/$REPO/rulesets" --jq ".[] | select(.name==\"$1\") | .id" 2>/dev/null; }

if [ -z "$(have protect-main)" ]; then
  gh api "repos/$REPO/rulesets" --method POST --silent --input - <<'JSON'
{
  "name": "protect-main",
  "target": "branch",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
  "bypass_actors": [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "pull_request"}],
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "pull_request", "parameters": {"required_approving_review_count": 1,
      "require_code_owner_review": true, "dismiss_stale_reviews_on_push": true,
      "require_last_push_approval": false, "required_review_thread_resolution": false}},
    {"type": "required_status_checks", "parameters": {"strict_required_status_checks_policy": false,
      "required_status_checks": [{"context": "test-build-push"}]}}
  ]
}
JSON
  echo "created ruleset protect-main"
fi
if [ -z "$(have keep-candidates)" ]; then
  gh api "repos/$REPO/rulesets" --method POST --silent --input - <<'JSON'
{
  "name": "keep-candidates",
  "target": "branch",
  "enforcement": "active",
  "conditions": {"ref_name": {"include": ["refs/heads/candidate/**"], "exclude": []}},
  "rules": [{"type": "deletion"}, {"type": "non_fast_forward"}]
}
JSON
  echo "created ruleset keep-candidates"
fi

# The bypass is repository admins only, through a pull request; neither App is an admin, so neither may appear here
bypass=$(gh api "repos/$REPO/rulesets/$(have protect-main)" --jq '.bypass_actors')
echo "protect-main bypass actors: $bypass"
if jq -e 'any(.[]; .actor_type == "Integration")' <<<"$bypass" >/dev/null; then
  echo "refused: a GitHub App can bypass protect-main; remove it" >&2; exit 1
fi
echo "GitHub controls in place. Add CODEOWNERS (see github/CODEOWNERS.snippet) with real reviewers."
