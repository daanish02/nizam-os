#!/usr/bin/env bash
# Writes scripts/check.sh at the project root: lint + format-check + tests for
# every stack present, in one command.
#
# Exists because verification_command is deliberately a single shell-free
# command (docs/DECISIONS.md D-005 — the `tee` bug), so a ticket cannot chain
# `ruff check && pytest` itself. Without this, lint ran only at pre-push and a
# lint error survived every ticket in between.
#
# Usage: write-check-script.sh   (run from the project root, after scaffolding)

set -euo pipefail

mkdir -p scripts

cat > scripts/check.sh <<'EOF'
#!/usr/bin/env bash
# Lint, format-check, and test every stack in this repo. One command, because
# a ticket's verification_command is a single shell-free command by design.
#
# Called per ticket by `plan.py verify`, and again before push by
# feanor/scripts/check-push.py. Exits non-zero if anything fails.
set -uo pipefail

failed=0
# `run` must NOT be called inside a ( subshell ): failed=1 set there cannot
# reach this shell, and the script would exit 0 with real failures. Pass the
# directory instead and let run do the cd in a subshell it controls.
run() {
    local dir="$1"; shift
    echo ""
    echo "---- ($dir) $* ----"
    if ! (cd "$dir" && "$@"); then
        echo "^^^ FAILED in $dir: $*" >&2
        failed=1
    fi
}

# Same as run, but treats one extra exit code as success.
run_allow() {
    local ok="$1"; shift
    local dir="$1"; shift
    echo ""
    echo "---- ($dir) $* ----"
    (cd "$dir" && "$@")
    local code=$?
    if [ "$code" -ne 0 ] && [ "$code" -ne "$ok" ]; then
        echo "^^^ FAILED in $dir: $*" >&2
        failed=1
    fi
}

for svc in backend services/*/; do
    [ -f "$svc/pyproject.toml" ] || continue
    run "$svc" uv run ruff check .
    run "$svc" uv run ruff format --check .
    # --exitfirst-safe: pytest exits 5 for "no tests collected", which is the
    # correct state for a freshly scaffolded package and must not fail the gate.
    # Real failures (exit 1) still fail. Drop this once the suite is populated.
    run_allow 5 "$svc" uv run pytest -m 'not slow' -q
done

for svc in backend services/*/; do
    [ -f "$svc/go.mod" ] || continue
    run "$svc" go vet ./...
    run "$svc" go test ./...
done

if [ -f frontend/package.json ]; then
    run frontend bun run lint
    run frontend bunx tsc --noEmit
fi

if [ "$failed" -ne 0 ]; then
    echo ""
    echo "=== checks FAILED ==="
    exit 1
fi
echo ""
echo "=== all checks passed ==="
EOF

chmod +x scripts/check.sh
echo "Wrote scripts/check.sh"
