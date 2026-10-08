#!/usr/bin/env bash
# Scaffolds a Python backend per conventions/python/project-layout.md +
# dependency-management.md. Run from the project root.
#
# Usage: python-backend.sh [--dir <target-dir>] <domain1> [domain2] ...
# Example (single-service, default): python-backend.sh orders billing
# Example (multi-service backend, per go-backend.sh's same convention):
#   python-backend.sh --dir services/api orders billing
set -e

TARGET_DIR="backend"
if [ "$1" = "--dir" ]; then
  TARGET_DIR="$2"
  shift 2
fi

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 [--dir <target-dir>] <domain1> [domain2] ..."
  exit 1
fi

# Preflight before writing anything: a missing or wrong-version toolchain
# should fail here, not halfway through with a half-scaffolded tree.
FEANOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
uv run "$FEANOR_DIR/scripts/check-toolchain.py" uv python

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

# --app --no-package is required, not optional: bare `uv init` defaults to a
# src/<package>/ layout, which violates project-layout.md's flat app/
# mandate. This was a real bug found by dry-running the plain `uv init` path.
uv init --app --no-package
rm -f main.py  # replaced by the real entry point below

# uv init sets requires-python from the local interpreter, not the floor
# python/project-layout.md pins (>=3.12,<3.13) — patch it explicitly. This was
# a real bug found by dry-running the script: a machine on Python 3.14 got
# requires-python = ">=3.14" baked into a scaffolded project.
# Not `sed -i`: GNU sed treats the next word as the script, BSD sed (macOS)
# treats it as a mandatory backup suffix, so the same line silently does two
# different things. Redirect to a temp file and move — portable everywhere.
sed 's/^requires-python = .*/requires-python = ">=3.12,<3.13"/' pyproject.toml > pyproject.toml.tmp
mv pyproject.toml.tmp pyproject.toml

# testing.md's testpaths convention isn't set by uv init either — add it,
# same dry-run-found gap as the line above.
cat >> pyproject.toml <<'EOF'

[tool.pytest.ini_options]
testpaths = ["tests"]
EOF

mkdir -p app/utils
# __init__.py, not just mkdir: git doesn't track empty directories, so
# without a real file inside, utils/ silently vanishes from the repo the
# moment anything commits — even though the scaffold genuinely created it.
# Found by testing a real commit after a real scaffold run. __init__.py is
# also correct on its own merits: utils/ is a real importable package per
# project-layout.md, same as every domain package below.
#
# Written with a docstring rather than `touch`ed empty: a package __init__.py is
# the one file that says what the package owns, and a live run produced 19 empty
# ones - nothing documented, and every import forced deep into submodules. The
# docstring is a stub for the agent to complete. __all__ is deliberately NOT
# pre-written: an empty __all__ on a fresh package exports nothing and silently
# breaks `from app.x import *`, so it is added once the package has a real
# public surface (see conventions/python/project-layout.md).
echo '"""Cross-domain helpers used by 2+ domain packages. Not a catch-all."""' > app/utils/__init__.py
for domain in "$@"; do
  mkdir -p "app/$domain" "tests/$domain"
  echo "\"\"\"$domain domain: models, service logic, and router.\"\"\"" > "app/$domain/__init__.py"
  # tests/ packages stay empty - a docstring there is noise, not documentation.
  touch "tests/$domain/__init__.py"
done
echo '"""Application package: domain packages, shared utils, and configuration."""' > app/__init__.py
touch tests/__init__.py

cat > tests/conftest.py <<'EOF'
"""Puts the backend root on sys.path so tests can import main.py and app/ directly."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
EOF

cat > main.py <<'EOF'
"""Entry point. Creates the app instance and wires routers/middleware/exception handlers."""

from fastapi import FastAPI

app = FastAPI()


@app.get("/health")
async def health() -> dict:
    """Liveness check."""
    return {"success": True, "data": {"status": "ok"}}
EOF

uv add fastapi uvicorn
uv add --dev pytest httpx ruff

# python/tooling.md is the source of truth for this block — keep in sync.
cat >> pyproject.toml <<'EOF'

[tool.ruff]
target-version = "py312"
line-length = 79

[tool.ruff.lint]
select = [
    "E", "W", "F", "I", "B", "UP", "SIM", "C4",
    "PIE", "RET", "RSE", "PTH", "N", "TRY",
]
ignore = ["COM812"]

[tool.ruff.lint.isort]
combine-as-imports = true

[tool.ruff.format]
quote-style = "double"
indent-style = "space"
line-ending = "auto"
EOF

echo "Scaffolded $TARGET_DIR/ with domains: $*"
