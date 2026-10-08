#!/usr/bin/env bash
# Whole-suite regression harness. Runs every service's tests in one command.
#
# NOT the per-ticket gate. /exec verifies a single ticket through
# `plan.py verify`, which runs that ticket's own verification_command without a
# shell and records its real exit code. This script is the broad sweep used by
# /standardize (prove a refactor broke nothing) and before a release.
#
# Usage: run-tests.sh [project-root]
set -euo pipefail

PROJECT_ROOT="${1:-.}"
cd "$PROJECT_ROOT"

failed=0
ran=0

run_suite() {
    local label="$1" dir="$2"
    shift 2
    echo ""
    echo "=== $label ($dir) ==="
    ran=$((ran + 1))
    if ( cd "$dir" && "$@" ); then
        echo "--- $label: PASS"
    else
        echo "--- $label: FAIL" >&2
        failed=$((failed + 1))
    fi
}

# Discover services the same way write-dev-scripts.sh does: services/<role>/ when
# the project has more than one backend, otherwise backend/. Keeping the two in
# sync matters — a service that start.sh launches but this never tests is a gap.
backend_dirs=()
if [ -d services ]; then
    for svc in services/*/; do
        [ -d "$svc" ] && backend_dirs+=("${svc%/}")
    done
elif [ -d backend ]; then
    backend_dirs+=("backend")
fi

for dir in "${backend_dirs[@]}"; do
    if [ -f "$dir/pyproject.toml" ]; then
        run_suite "Python" "$dir" uv run pytest
    elif [ -f "$dir/go.mod" ]; then
        # -race is mandatory in CI per cross-stack/security.md.
        run_suite "Go" "$dir" go test -race ./...
    else
        echo "WARNING: $dir has no pyproject.toml or go.mod — skipped" >&2
    fi
done

# Frontend is Bun, never npm — see nextjs/dependency-management.md.
if [ -f frontend/package.json ]; then
    run_suite "Frontend" "frontend" bun test
fi

# Single-package repo with no backend/ or frontend/ split.
if [ "$ran" -eq 0 ]; then
    if [ -f pyproject.toml ]; then
        run_suite "Python (root)" "." uv run pytest
    elif [ -f go.mod ]; then
        run_suite "Go (root)" "." go test -race ./...
    elif [ -f package.json ]; then
        run_suite "Frontend (root)" "." bun test
    fi
fi

echo ""
if [ "$ran" -eq 0 ]; then
    echo "No test suite found. Nothing was verified — this is a failure, not a pass." >&2
    exit 1
fi

if [ "$failed" -gt 0 ]; then
    echo "=== $failed of $ran suite(s) FAILED ===" >&2
    exit 1
fi

echo "=== All $ran suite(s) passed ==="
