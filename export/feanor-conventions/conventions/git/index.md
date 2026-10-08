---
type: catalog
title: Git Conventions Index
description: Branching model, commit format, pre-commit hooks, and per-branch test gates enforced across all Feanor-managed projects.
applies_to: [git]
tags: [git, index]
---

# Git Conventions

- [branch-strategy.md](./branch-strategy.md) - Branch hierarchy (`main` <- `qa` <- feature branches), naming prefixes, hotfix/release flow.
- [commit-format.md](./commit-format.md) - Conventional Commits format, subject/body rules, commit grouping.
- [pre-commit-hooks.md](./pre-commit-hooks.md) - Required local hooks: ruff lint+format, hygiene checks.
- [branch-test-tiers.md](./branch-test-tiers.md) - Test scope required to merge into each branch tier, security gate on `main`.
- [dependabot.md](./dependabot.md) - Automated dependency updates across uv, Bun, and Go modules.
- [github-repo-setup.md](./github-repo-setup.md) - When and how to create the GitHub repo, branch protection, merge-method restriction, CI backstop for the feanor-scoping rule.
