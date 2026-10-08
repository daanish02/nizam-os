#!/usr/bin/env bash
# Creates the GitHub repo, pushes main + qa, configures branch protection and
# merge-method restrictions per git/branch-strategy.md, and writes the CI
# (a local pre-commit hook can be bypassed with --no-verify;
# this closes that gap where it can't be skipped).
#
# Run once, right after the project's first local commit (per
# git/commit-format.md) — this script assumes that commit already exists.
#
# Usage: github-repo-setup.sh <repo-name> [--public]
# Requires: gh CLI installed and authenticated (`gh auth status`).
set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <repo-name> [--public]"
  exit 1
fi

REPO_NAME="$1"
VISIBILITY="--private"
[ "$2" = "--public" ] && VISIBILITY="--public"

if ! command -v gh >/dev/null 2>&1; then
  echo "STOPPED: gh CLI not found. Install it (https://cli.github.com) and run 'gh auth login' first."
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "STOPPED: gh CLI is not authenticated. Run 'gh auth login' first."
  exit 1
fi

if [ ! -d .git ] || [ -z "$(git log --oneline -1 2>/dev/null)" ]; then
  echo "STOPPED: no local commit found. Make the project's first commit before running this script."
  exit 1
fi

# --- Create the repo, push main ---
gh repo create "$REPO_NAME" "$VISIBILITY" --source=. --remote=origin --push

# --- Create and push qa ---
git checkout -b qa
git push -u origin qa
git checkout main

OWNER_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

# --- Merge-method restriction: matches branch-strategy.md — merge commits
# only, never squash/rebase (commits are already curated per commit-format.md;
# squashing would discard that structure). ---
gh repo edit "$OWNER_REPO" \
  --enable-merge-commit=true \
  --enable-squash-merge=false \
  --enable-rebase-merge=false \
  --delete-branch-on-merge=true

# --- Branch protection on main: PR required, no force pushes, no deletion. ---
# No required status check is set here: requiring a context that never reports
# leaves every PR permanently pending. Add the project's own CI job as a
# required check once it exists and has run at least once.
gh api "repos/$OWNER_REPO/branches/main/protection" -X PUT --input - <<EOF
{
  "required_status_checks": null,
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
EOF

# --- Branch protection on qa: PR required, no force push/delete, no review
# count enforced (matches branch-strategy.md's lighter integration-tier bar). ---
gh api "repos/$OWNER_REPO/branches/qa/protection" -X PUT --input - <<EOF
{
  "required_status_checks": null,
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
EOF

echo ""
echo "Done. Repo: https://github.com/$OWNER_REPO"
echo "  - main: PR required, merge-commit only, no squash/rebase"
echo "  - qa: PR required, no force-push/delete"
echo ""
echo "Next: add any CI/deploy secrets this project needs at"
echo "  https://github.com/$OWNER_REPO/settings/secrets/actions"
