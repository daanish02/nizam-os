#!/usr/bin/env bash
# Deterministically writes .github/dependabot.yml, per
# conventions/git/dependabot.md. Called by /scaffold instead of having the
# agent retype the YAML from that doc each run.
#
# Usage: write-dependabot-config.sh <stack1> [stack2] ...
# Stacks: python (uv ecosystem, path backend/ or services/*), go (gomod),
#         nextjs (bun ecosystem, path frontend/)
# Example: write-dependabot-config.sh python nextjs
set -e

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <stack1> [stack2] ..."
  echo "Stacks: python, go, nextjs"
  exit 1
fi

mkdir -p .github

# Backend directory field: `directory` (singular) does NOT support globs at
# all — confirmed against GitHub's own docs, not assumed. Multi-service
# projects (services/<role>/, per python|go/project-layout.md) need
# `directories` (plural, a list, the only field with glob support) instead.
MULTI_SERVICE=false
[ -d "services" ] && MULTI_SERVICE=true

{
  echo "version: 2"
  echo "updates:"

  for s in "$@"; do
    case "$s" in
      python)
        if [ "$MULTI_SERVICE" = true ]; then
          cat <<'EOF'
  - package-ecosystem: "uv"
    directories:
      - "/services/*"
    schedule:
      interval: "weekly"
    groups:
      backend-deps:
        patterns: ["*"]
    open-pull-requests-limit: 5
EOF
        else
          cat <<'EOF'
  - package-ecosystem: "uv"
    directory: "/backend"
    schedule:
      interval: "weekly"
    groups:
      backend-deps:
        patterns: ["*"]
    open-pull-requests-limit: 5
EOF
        fi
        ;;
      go)
        if [ "$MULTI_SERVICE" = true ]; then
          cat <<'EOF'
  - package-ecosystem: "gomod"
    directories:
      - "/services/*"
    schedule:
      interval: "weekly"
    groups:
      backend-deps:
        patterns: ["*"]
    open-pull-requests-limit: 5
EOF
        else
          cat <<'EOF'
  - package-ecosystem: "gomod"
    directory: "/backend"
    schedule:
      interval: "weekly"
    groups:
      backend-deps:
        patterns: ["*"]
    open-pull-requests-limit: 5
EOF
        fi
        ;;
      nextjs)
        cat <<'EOF'
  - package-ecosystem: "bun"
    directory: "/frontend"
    schedule:
      interval: "weekly"
    groups:
      frontend-deps:
        patterns: ["*"]
    open-pull-requests-limit: 5
EOF
        ;;
      *)
        echo "Unknown stack: $s (expected python, go, or nextjs)" >&2
        exit 1
        ;;
    esac
  done

  cat <<'EOF'
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
EOF
} > .github/dependabot.yml

echo "Wrote .github/dependabot.yml for: $*"
