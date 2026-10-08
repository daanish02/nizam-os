# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Branch and commit discipline gate.

`conventions/git/branch-strategy.md` and `git/commit-format.md` are complete and
correct, and across a full live run neither was followed: the project had only
`main` in its history and contained single commits of 74 files / 8647 lines.
Nothing failed, because nothing checked. Prose is silent when skipped — see
`meta/determinism-standard.md`'s enforcement ladder.

This script checks only what is mechanically decidable. Whether a change is *one
logical change* is judgment and stays in `commit-format.md`, which the resolver
now loads for every ticket.

Usage (from project root):
  uv run feanor/scripts/check-git.py branch                    # before /exec
  uv run feanor/scripts/check-git.py commit                    # before git commit
  uv run feanor/scripts/check-git.py commit -m "feat(x): add y"

Exits 0 when the action may proceed, 1 naming what to fix.
`--override "<reason>"` proceeds and records the reason in
.feanor/logs/overrides.log.
"""

import argparse
import re
import subprocess
import sys

from _gate import add_override_arg, finish

PROTECTED = ("main", "qa")
BRANCH_PATTERN = re.compile(r"^(feature|fix|hotfix|release)/[a-z0-9][a-z0-9._-]*$")
COMMIT_PATTERN = re.compile(
    r"^(feat|fix|perf|docs|chore|refactor|test)(\([a-z0-9._/-]+\))?: [a-z].*[^.]$"
)
# A ticket touches 1-3 files by construction (planner atomic-isolation rule), so
# a much larger staged set usually means several tickets batched into one commit.
# Only ever a warning: "one logical change" is judgment, and a heuristic that
# blocks gets overridden reflexively until nobody reads it.
STAGED_FILE_BUDGET = 10


def git(*args: str) -> tuple[int, str]:
    proc = subprocess.run(["git", *args], capture_output=True, text=True)
    return proc.returncode, (proc.stdout + proc.stderr).strip()


def current_branch() -> str | None:
    code, out = git("symbolic-ref", "--short", "HEAD")
    return out if code == 0 else None


def check_branch(failures: list[str], warnings: list[str]) -> None:
    branch = current_branch()
    if branch is None:
        failures.append(
            "not on a branch (detached HEAD or no commits yet) — "
            "check out a branch before working"
        )
        return

    if branch in PROTECTED:
        failures.append(
            f"on '{branch}' — work never happens directly on {' or '.join(PROTECTED)}.\n"
            f"        Cut a branch first:  git checkout -b feature/<short-kebab-description>\n"
            f"        See conventions/git/branch-strategy.md"
        )
    elif not BRANCH_PATTERN.match(branch):
        failures.append(
            f"branch '{branch}' does not match <prefix>/<kebab-description>, "
            f"prefix one of feature|fix|hotfix|release "
            f"(conventions/git/branch-strategy.md)"
        )


def check_commit(failures: list[str], warnings: list[str], message: str | None) -> None:
    check_branch(failures, warnings)

    code, staged = git("diff", "--cached", "--name-only")
    if code != 0:
        failures.append("not a git repository")
        return

    files = [line for line in staged.splitlines() if line.strip()]
    if not files:
        failures.append(
            "nothing staged — stage the ticket's target_files explicitly "
            "(never `git add -A`)"
        )
    elif len(files) > STAGED_FILE_BUDGET:
        warnings.append(
            f"{len(files)} files staged (budget {STAGED_FILE_BUDGET}). A ticket touches "
            f"1-3 files by construction, so this is usually several tickets batched "
            f"into one commit — commit each ticket as it completes. Not blocking: "
            f"whether this is one logical change is your call, not the script's."
        )

    if message is not None and not COMMIT_PATTERN.match(message.splitlines()[0]):
        failures.append(
            f"commit subject does not match Conventional Commits:\n"
            f"        {message.splitlines()[0]!r}\n"
            f"        Expected: type(scope): imperative subject   "
            f"[type: feat|fix|perf|docs|chore|refactor|test]\n"
            f"        Lowercase, no trailing period. See conventions/git/commit-format.md"
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("branch", "commit"))
    parser.add_argument(
        "-m", "--message", help="commit subject to validate (commit mode only)"
    )
    add_override_arg(parser)
    args = parser.parse_args()

    failures: list[str] = []
    warnings: list[str] = []

    if args.mode == "branch":
        check_branch(failures, warnings)
    else:
        check_commit(failures, warnings, args.message)

    finish(
        f"git {args.mode} discipline",
        failures,
        warnings=warnings,
        override=args.override,
        ok_message=f"OK — git {args.mode} discipline satisfied.",
    )


if __name__ == "__main__":
    main()
