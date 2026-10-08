---
type: convention
title: Python Tooling Config
description: Verbatim Ruff lint + format baseline for pyproject.toml, rule-by-rule rationale, documented opt-in rules, and CI/pre-commit commands.
applies_to: [python]
tags: [python, tooling, ruff, linting, formatting]
---

# Python Tooling Config

Ruff replaces flake8, isort, and black — do not add any of those alongside it.

## pyproject.toml Baseline

```toml
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
```

`line-length = 79` is PEP 8's actual limit, not the more common 88/100 seen
in other Ruff/Black setups — a deliberate choice for feanor Python projects.
`E501` (line-too-long) stays selected rather than ignored: at 79 columns it's
still catching real overflows the formatter can't wrap for you (long string
literals, URLs in comments), so it isn't formatter-redundant the way it would
be at a wider line length.

`COM812` (missing trailing comma) is ignored because it conflicts with the
Ruff formatter's own trailing-comma handling — Ruff's own docs flag this
combination as one to avoid.

This diverges from `typescript/tooling.md`'s `lineWidth: 100` on purpose —
Python and TypeScript don't need matching line lengths; PEP 8 is Python's own
long-standing convention.

## Rule Table

| Code | Purpose |
| :--- | :--- |
| `E`, `W` | pycodestyle errors/warnings — basic PEP 8 style |
| `F` | Pyflakes — undefined names, unused imports, real bugs |
| `I` | isort — import sorting |
| `B` | flake8-bugbear — common Python footguns |
| `UP` | pyupgrade — modern syntax for the pinned Python version (`list[int]` not `List[int]`) |
| `SIM` | flake8-simplify — unnecessarily complicated code |
| `C4` | flake8-comprehensions — better comprehensions |
| `PIE` | flake8-pie — misc. unnecessary code |
| `RET` | flake8-return — problematic return patterns |
| `RSE` | flake8-raise — exception-raising style |
| `PTH` | flake8-use-pathlib — `pathlib` over `os.path` |
| `N` | pep8-naming — naming convention violations |
| `TRY` | flake8-try-except-raise — exception hygiene (broad `except`, bad `raise`), pairs with `RET`/`RSE` |

## Documented Opt-Ins (not in the default select list)

These are real, useful rules — excluded from the baseline because they're
false-positive-heavy against this repo's own conventions, not because they're
low quality. Add them per-project once the noise is worth it:

- **`ARG`** (unused-argument) — fires constantly on FastAPI route handlers
  and pytest fixtures, both of which take arguments they don't use by design
  (dependency injection, fixture request objects).
- **`ERA`** (commented-out code) — a habit rule, not a bug-finder; flags
  legitimate example code in docstrings/comments as often as it catches dead
  code.
- **`PL`** (full Pylint) — high false-positive rate on ordinary
  FastAPI/Pydantic code (`too-many-arguments`, `magic-value-comparison`).
  If adopted, start narrow (`PLE` only) rather than enabling the whole family.

## CI

- `uv run ruff check .` and `uv run ruff format --check .` must both pass
  before merge.

## Pre-commit

- `uv run ruff check --fix` and `uv run ruff format` run on staged files.
- Hook configuration: see [`../git/pre-commit-hooks.md`](../git/pre-commit-hooks.md).
