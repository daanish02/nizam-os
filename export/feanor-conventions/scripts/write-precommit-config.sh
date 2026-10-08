#!/usr/bin/env bash
# Deterministically writes .pre-commit-config.yaml at the project root, per
# conventions/git/pre-commit-hooks.md. Called by /scaffold instead of
# having the agent retype the YAML from that doc each run — this content
# never varies for a given stack combination, so it belongs in a script,
# not re-derived from prose every time (meta/determinism-standard.md).
#
# Usage: write-precommit-config.sh <stack1> [stack2] ...
# Stacks: python, go, nextjs
# Example: write-precommit-config.sh python nextjs
set -e

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <stack1> [stack2] ..."
  echo "Stacks: python, go, nextjs"
  exit 1
fi

HAS_PYTHON=false
HAS_GO=false
HAS_NEXTJS=false
for s in "$@"; do
  case "$s" in
    python) HAS_PYTHON=true ;;
    go) HAS_GO=true ;;
    nextjs) HAS_NEXTJS=true ;;
    *) echo "Unknown stack: $s (expected python, go, or nextjs)"; exit 1 ;;
  esac
done

{
  echo "repos:"

  if [ "$HAS_PYTHON" = true ]; then
    cat <<'EOF'
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.8.0
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
EOF
  fi

  if [ "$HAS_GO" = true ]; then
    cat <<'EOF'
  - repo: https://github.com/golangci/golangci-lint
    rev: v1.62.0
    hooks:
      - id: golangci-lint
  - repo: local
    hooks:
      - id: gofmt
        name: gofmt
        entry: gofmt -l -w
        language: system
        types: [go]
EOF
  fi

  if [ "$HAS_NEXTJS" = true ]; then
    cat <<'EOF'
  - repo: local
    hooks:
      - id: biome-check
        name: biome check
        entry: bunx biome check --write
        language: system
        types_or: [ts, tsx, javascript, jsx, json]
EOF
  fi

  cat <<'EOF'
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-merge-conflict
      - id: check-added-large-files
EOF
} > .pre-commit-config.yaml

echo "Wrote .pre-commit-config.yaml for: $*"
echo "Pinned hook revisions are current as of this script's own last update — bump them periodically, they're not auto-tracked."
