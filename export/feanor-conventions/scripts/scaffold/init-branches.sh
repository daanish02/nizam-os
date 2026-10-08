#!/usr/bin/env bash
# Creates the branch structure from conventions/git/branch-strategy.md:
# feature/* -> qa -> main. Idempotent — safe to re-run.
#
# Exists because in a full live run the structure was never created and every
# commit landed on main. The convention was complete and correct; nothing acted
# on it. See meta/determinism-standard.md on prose being silent when skipped.
#
# Usage:
#   bash feanor/scripts/scaffold/init-branches.sh <slug>
#
# <slug> is the feature branch's kebab-case description, chosen by the agent
# (that part is judgment). Everything else here is mechanical.

set -euo pipefail

SLUG="${1:-}"
if [ -z "$SLUG" ]; then
    echo "usage: init-branches.sh <kebab-slug>   e.g. init-branches.sh booking-platform" >&2
    exit 1
fi

if ! printf '%s' "$SLUG" | grep -Eq '^[a-z0-9][a-z0-9._-]*$'; then
    echo "init-branches: slug '$SLUG' must be lowercase kebab-case (a-z, 0-9, - . _)" >&2
    exit 1
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "init-branches: not a git repository — run 'git init' first." >&2
    exit 1
fi

# An unborn HEAD has no commit to branch from, and `git branch qa` would fail.
if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "init-branches: repository has no commits yet." >&2
    echo "Make the initial commit first, then re-run." >&2
    exit 1
fi

if git rev-parse --verify --quiet qa >/dev/null; then
    echo "qa already exists — leaving it alone."
else
    git branch qa
    echo "Created qa."
fi

BRANCH="feature/$SLUG"
if git rev-parse --verify --quiet "$BRANCH" >/dev/null; then
    git checkout "$BRANCH"
    echo "Switched to existing $BRANCH."
else
    # Cut from qa, per branch-strategy.md: feature branches target qa, not main.
    git checkout -b "$BRANCH" qa
    echo "Created $BRANCH from qa."
fi

echo ""
echo "Branch structure ready:  $BRANCH -> qa -> main"
echo "Work happens on $BRANCH. Nothing commits directly to qa or main."
