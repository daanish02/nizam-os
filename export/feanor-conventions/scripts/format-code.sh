#!/usr/bin/env bash
set -e

# Code formatting utility script
TARGET_DIR="${1:-.}"

echo "=== Formatting Target Codebase ==="

if command -v ruff &> /dev/null; then
    echo "Formatting Python files with ruff..."
    ruff format "$TARGET_DIR" || true
    ruff check --fix "$TARGET_DIR" || true
fi

if command -v prettier &> /dev/null; then
    echo "Formatting Web/JSON files with prettier..."
    prettier --write "$TARGET_DIR/**/*.{json,md,js,ts}" --ignore-path .gitignore || true
fi

echo "=== Formatting Complete ==="