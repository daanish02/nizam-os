#!/usr/bin/env bash
# Runs every Feanor self-consistency gate. One entry point, so the checks cannot
# be skipped by forgetting which ones exist.
#
# A check that exists but nothing invokes is still just a suggestion — this is
# what makes them gates. Called by the pre-commit hook and by /audit.
#
# Usage:
#   bash feanor/scripts/check-all.sh                 # feanor's own consistency
#   bash feanor/scripts/check-all.sh --project       # also audit the target project
#
# Exits non-zero if any gate fails. Individual gates accept --override; this
# wrapper deliberately does not, so a bypass is per-check and recorded.
set -uo pipefail

FEANOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INCLUDE_PROJECT=0
[ "${1:-}" = "--project" ] && INCLUDE_PROJECT=1

if ! command -v uv >/dev/null 2>&1; then
    echo "check-all: uv is not on PATH — cannot run the gates." >&2
    exit 1
fi

failed=0

run_gate() {
    local label="$1"
    shift
    echo ""
    echo "──────── $label ────────"
    if "$@"; then
        return 0
    fi
    echo "^^^ $label FAILED" >&2
    failed=$((failed + 1))
}

run_gate "frontmatter + tag map" uv run "$FEANOR_DIR/scripts/validate-okf.py" --quiet
run_gate "tag resolution"        uv run "$FEANOR_DIR/scripts/resolve-context.py" --validate
run_gate "registration"          uv run "$FEANOR_DIR/scripts/check-registration.py"

if [ "$INCLUDE_PROJECT" -eq 1 ]; then
    run_gate "mechanical conventions" uv run "$FEANOR_DIR/scripts/audit-mechanical.py"
fi

echo ""
if [ "$failed" -gt 0 ]; then
    echo "=== $failed gate(s) FAILED ==="
    echo "Fix them, or re-run the specific gate with --override \"<reason>\"."
    exit 1
fi

echo "=== All gates passed ==="
