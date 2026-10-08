# /// script
# requires-python = ">=3.12"
# dependencies = ["pyyaml"]
# ///
"""Mechanical convention checks against a target project. Runs before /audit's judgment work.

/audit's convention-compliance step is otherwise entirely judgment, so two runs
disagree on the same codebase. This script decides the subset of conventions that
a file test, config parse, or token search can settle with no interpretation,
giving the LLM a stable base to reason on top of.

Every check cites the convention file it enforces, so a finding is traceable to a
rule rather than to a model's opinion.

Deliberately EXCLUDED, because they need to understand intent and would produce
false positives that train people to ignore the tool: whether an ownership
predicate is in the right WHERE clause, whether a Go name stutters, whether
pagination is genuinely cursor-based, whether logging avoids interpolation,
whether DB roles are least-privilege. Those stay LLM judgment in /audit.

Usage (from project root):
  uv run feanor/scripts/audit-mechanical.py
  uv run feanor/scripts/audit-mechanical.py --json
  uv run feanor/scripts/audit-mechanical.py --override "greenfield, not yet wired"
"""

import argparse
import json
import re
import sys
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:
    from _gate import require_uv_run

    require_uv_run("pyyaml")

from _gate import add_override_arg, finish

SOURCE_DIRS = ("backend", "frontend", "services", "src", "app", "cmd", "internal")
SKIP_PARTS = {
    ".git", "node_modules", ".venv", "venv", "__pycache__", "dist", "build",
    ".next", "vendor", "feanor", ".feanor", "graphify-out", ".mypy_cache",
}


@dataclass
class Finding:
    severity: str          # CRIT | HIGH | MED
    rule: str              # convention file that mandates it
    message: str
    location: str = ""

    def line(self) -> str:
        where = f" [{self.location}]" if self.location else ""
        return f"{self.severity:4}  {self.message}{where}  ({self.rule})"


@dataclass
class Context:
    root: Path
    findings: list[Finding] = field(default_factory=list)

    def add(self, severity: str, rule: str, message: str, location: str = "") -> None:
        self.findings.append(Finding(severity, rule, message, location))

    def exists(self, *parts: str) -> bool:
        return (self.root / Path(*parts)).exists()

    def read(self, *parts: str) -> str:
        path = self.root / Path(*parts)
        try:
            return path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            return ""

    def source_files(self, *suffixes: str) -> list[Path]:
        out = []
        for path in self.root.rglob("*"):
            if not path.is_file() or path.suffix not in suffixes:
                continue
            if any(part in SKIP_PARTS for part in path.relative_to(self.root).parts):
                continue
            out.append(path)
        return out

    def rel(self, path: Path) -> str:
        return path.relative_to(self.root).as_posix()


# ─────────────────────────── Tier A: files and config ───────────────────────────

def check_lockfiles(ctx: Context) -> None:
    """A lockfile that is not committed means CI tested something other than what ships."""
    rule = "cross-stack/supply-chain.md"
    # Each manifest maps to every lockfile format that satisfies it. Bun ships
    # `bun.lock` (text) by default now and `bun.lockb` (binary) only on older
    # versions — accepting just one of them fails every project on the other.
    pairs = [
        ("pyproject.toml", ("uv.lock",), "Python"),
        ("go.mod", ("go.sum",), "Go"),
        ("package.json", ("bun.lock", "bun.lockb", "package-lock.json"), "JS"),
    ]
    for manifest, lockfiles, label in pairs:
        for manifest_path in ctx.root.rglob(manifest):
            if any(p in SKIP_PARTS for p in manifest_path.relative_to(ctx.root).parts):
                continue
            directory = manifest_path.parent
            if not any((directory / name).exists() for name in lockfiles):
                ctx.add(
                    "CRIT",
                    rule,
                    f"{label} project has no lockfile (expected one of: {', '.join(lockfiles)})",
                    ctx.rel(directory),
                )


def check_env_hygiene(ctx: Context) -> None:
    rule = "cross-stack/secrets-management.md"
    gitignore = ctx.read(".gitignore")
    if not gitignore:
        ctx.add("CRIT", rule, "no .gitignore at the repo root")
    elif not re.search(r"^\s*\.env\s*$", gitignore, re.MULTILINE):
        ctx.add("CRIT", rule, ".env is not gitignored")
    if not ctx.exists(".env.example"):
        ctx.add("HIGH", rule, ".env.example is missing — it is the contract for required config")


def check_env_completeness(ctx: Context) -> None:
    """Every env key read in code must appear in .env.example (W5)."""
    rule = "cross-stack/secrets-management.md"
    example = ctx.read(".env.example")
    if not example:
        return

    declared = set(re.findall(r"^\s*([A-Z][A-Z0-9_]{2,})\s*=", example, re.MULTILINE))
    patterns = [
        r"os\.getenv\(\s*[\"']([A-Z][A-Z0-9_]{2,})[\"']",
        r"os\.environ\[\s*[\"']([A-Z][A-Z0-9_]{2,})[\"']",
        r"os\.Getenv\(\s*\"([A-Z][A-Z0-9_]{2,})\"",
        r"process\.env\.([A-Z][A-Z0-9_]{2,})",
        r"process\.env\[\s*[\"']([A-Z][A-Z0-9_]{2,})[\"']",
    ]
    used: dict[str, str] = {}
    for path in ctx.source_files(".py", ".go", ".ts", ".tsx", ".js"):
        text = path.read_text(encoding="utf-8", errors="replace")
        for pattern in patterns:
            for key in re.findall(pattern, text):
                used.setdefault(key, ctx.rel(path))

    for key, where in sorted(used.items()):
        if key not in declared and key not in {"NODE_ENV", "PATH", "HOME", "CI"}:
            ctx.add("HIGH", rule, f"env var {key} is read in code but absent from .env.example", where)


def check_dockerfiles(ctx: Context) -> None:
    rule = "cross-stack/supply-chain.md"

    # A deployable unit with no Dockerfile at all. Previously this check only
    # validated Dockerfiles that existed, so a project with none passed clean —
    # which is exactly what a live run shipped. Each independently deployable
    # directory needs its own image; there is no root Dockerfile.
    deployable: list[Path] = []
    for marker in ("pyproject.toml", "go.mod", "package.json"):
        for manifest in ctx.root.rglob(marker):
            if any(p in SKIP_PARTS for p in manifest.relative_to(ctx.root).parts):
                continue
            deployable.append(manifest.parent)
    for directory in sorted(set(deployable)):
        if not (directory / "Dockerfile").is_file():
            ctx.add("HIGH", "ops/index.md", "deployable service has no Dockerfile", ctx.rel(directory))
        elif not (directory / ".dockerignore").is_file():
            ctx.add(
                "MED", "ops/index.md",
                "Dockerfile with no .dockerignore — build context ships .git/.env and caches",
                ctx.rel(directory),
            )

    for path in ctx.root.rglob("Dockerfile*"):
        if any(p in SKIP_PARTS for p in path.relative_to(ctx.root).parts):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        where = ctx.rel(path)
        for match in re.finditer(r"^FROM\s+(\S+)", text, re.MULTILINE):
            image = match.group(1)
            if image.endswith(":latest") or ":" not in image.rsplit("/", 1)[-1]:
                ctx.add("CRIT", rule, f"unpinned base image '{image}'", where)
        if not re.search(r"^USER\s+(?!root)", text, re.MULTILINE):
            ctx.add("HIGH", "ops/index.md", "Dockerfile has no non-root USER", where)


def check_framework_pins(ctx: Context) -> None:
    """Installed framework versions must match conventions/versions.toml.

    A scaffold script pinned the version at creation; nothing stopped a later
    `bun add next@16` from moving off it. This catches that drift. The live run
    that motivated the pin shipped Next 16.3.4 against a documented ~15.3.0.
    """
    rule = "conventions/versions.toml"
    versions_file = Path(__file__).resolve().parent.parent / "conventions" / "versions.toml"
    if not versions_file.is_file():
        return
    frameworks = tomllib.loads(versions_file.read_text(encoding="utf-8")).get("frameworks", {})

    for manifest in ctx.root.rglob("package.json"):
        if any(p in SKIP_PARTS for p in manifest.relative_to(ctx.root).parts):
            continue
        try:
            data = json.loads(manifest.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        declared = {**data.get("dependencies", {}), **data.get("devDependencies", {})}
        for name, spec in frameworks.items():
            wanted = spec.get("verify")
            if not wanted or name not in declared:
                continue
            actual = declared[name].lstrip("^~>=< ")
            # Only judge a version specific enough to judge. `"^5"` is a valid
            # caret range meaning any 5.x, not a pin violation — comparing bare
            # "5" against ">=5.8.0" would flag every freshly scaffolded project.
            # Ranges are the lockfile's business; this check is about a declared
            # version that has drifted off the pinned minor.
            if not re.match(r"^\d+\.\d+", actual):
                continue
            if not _satisfies(actual, wanted):
                ctx.add(
                    "HIGH", rule,
                    f"{name} {actual} is outside the pinned {wanted}",
                    ctx.rel(manifest),
                )


def _satisfies(version: str, spec: str) -> bool:
    """Mirrors check-toolchain.py's comparison for the subset of ranges used here."""
    actual = tuple(int(x) for x in version.split("."))
    for clause in spec.split(","):
        m = re.match(r"^(>=|<=|>|<|==)\s*(\d+(?:\.\d+)*)$", clause.strip())
        if not m:
            return False
        op, raw = m.groups()
        want = tuple(int(x) for x in raw.split("."))
        left = actual[: len(want)]
        if op == ">=" and not left >= want: return False
        if op == "<=" and not left <= want: return False
        if op == ">" and not left > want: return False
        if op == "<" and not actual < want: return False
        if op == "==" and left != want: return False
    return True


def check_logging_setup(ctx: Context) -> None:
    """A backend service with no structured-logging module.

    Logging is baseline (docs/DECISIONS.md D-009) — nothing is diagnosable
    without it. It used to be written only when an /exec ticket carried the
    observability tag; no ticket did, and a full live run shipped a service
    with no logger at all.
    """
    rule = "cross-stack/observability-logging.md"
    candidates = {
        "pyproject.toml": ("app/core/logging.py", "app/core/logger.py"),
        "go.mod": ("internal/infra/logger.go", "internal/logger/logger.go"),
    }
    for marker, expected in candidates.items():
        for manifest in ctx.root.rglob(marker):
            if any(p in SKIP_PARTS for p in manifest.relative_to(ctx.root).parts):
                continue
            directory = manifest.parent
            if not any((directory / rel).is_file() for rel in expected):
                ctx.add(
                    "HIGH", rule,
                    f"backend service has no structured-logging module (expected {expected[0]})",
                    ctx.rel(directory),
                )


def check_scaffold_matches(ctx: Context) -> None:
    """Directories declared in docs/SCAFFOLD.md must exist on disk.

    SCAFFOLD.md is the structure /scaffold was told to build, so a declared
    directory that does not exist means the build did not finish or the
    document drifted. Only checkable because the document records decisions
    rather than a listing of whatever happens to be there.
    """
    rule = "templates/high-level-docs/scaffold-template.md"
    text = ctx.read("docs", "SCAFFOLD.md")
    if not text:
        return

    # Backticked paths in the tables: `backend/`, `services/api/`, `app/orders/`.
    # Placeholders ({{...}}) and bare filenames are not directories to check.
    seen: set[str] = set()
    for raw in re.findall(r"`([A-Za-z0-9_./-]+/)`", text):
        candidate = raw.strip("/")
        if not candidate or "{{" in candidate or candidate in seen:
            continue
        seen.add(candidate)
        # A domain path is written relative to its service (`app/orders/`), so
        # resolve against each service root as well as the repo root before
        # calling it missing.
        roots = [ctx.root]
        for marker in ("pyproject.toml", "go.mod", "package.json"):
            for manifest in ctx.root.rglob(marker):
                if not any(x in SKIP_PARTS for x in manifest.relative_to(ctx.root).parts):
                    roots.append(manifest.parent)
        if not any((root / candidate).is_dir() for root in roots):
            ctx.add(
                "MED", rule,
                f"docs/SCAFFOLD.md declares {raw} but it does not exist on disk",
                "docs/SCAFFOLD.md",
            )


def check_ci_action_pinning(ctx: Context) -> None:
    rule = "cross-stack/supply-chain.md"
    workflows = ctx.root / ".github" / "workflows"
    if not workflows.is_dir():
        return
    for path in workflows.glob("*.y*ml"):
        text = path.read_text(encoding="utf-8", errors="replace")
        for match in re.finditer(r"uses:\s*([^\s@]+)@([^\s#]+)", text):
            action, ref = match.group(1), match.group(2)
            if action.startswith("./"):
                continue
            if not re.fullmatch(r"[0-9a-f]{40}", ref):
                ctx.add("HIGH", rule, f"CI action {action}@{ref} is not pinned to a commit SHA", ctx.rel(path))


def check_precommit(ctx: Context) -> None:
    rule = "git/pre-commit-hooks.md"
    if not ctx.exists(".pre-commit-config.yaml"):
        ctx.add("HIGH", rule, ".pre-commit-config.yaml is missing")
        return
    try:
        config = yaml.safe_load(ctx.read(".pre-commit-config.yaml")) or {}
    except yaml.YAMLError as exc:
        ctx.add("HIGH", rule, f".pre-commit-config.yaml is not valid YAML: {exc}")
        return
    text = ctx.read(".pre-commit-config.yaml")
    for repo in config.get("repos", []):
        rev = str(repo.get("rev", ""))
        if repo.get("repo") == "local":
            continue
        if rev in {"", "main", "master", "HEAD"}:
            ctx.add("CRIT", rule, f"pre-commit repo {repo.get('repo')} has unpinned rev '{rev}'")
    if "gitleaks" not in text:
        ctx.add("HIGH", "cross-stack/secrets-management.md", "no gitleaks hook — secrets can reach a commit")


def check_dependabot(ctx: Context) -> None:
    rule = "git/dependabot.md"
    if not ctx.exists(".github", "dependabot.yml"):
        ctx.add("MED", rule, ".github/dependabot.yml is missing")


def check_migrations(ctx: Context) -> None:
    rule = "cross-stack/database.md"
    for migrations in ctx.root.rglob("migrations"):
        if not migrations.is_dir():
            continue
        if any(p in SKIP_PARTS for p in migrations.relative_to(ctx.root).parts):
            continue
        for path in migrations.glob("*.sql"):
            if re.search(r"(down|rollback)", path.stem, re.IGNORECASE):
                ctx.add("CRIT", rule, f"down migration '{path.name}' — migrations are forward-only", ctx.rel(migrations))
            elif not re.match(r"^\d{3,}[_-]", path.stem):
                ctx.add("MED", rule, f"migration '{path.name}' is not zero-padded and numbered", ctx.rel(migrations))


def check_security_docs(ctx: Context) -> None:
    """Required when the capability profile says the project needs them."""
    profile_path = ctx.root / ".feanor" / "profile.toml"
    if not profile_path.exists():
        return
    import tomllib
    with profile_path.open("rb") as f:
        conditional = tomllib.load(f).get("conditional", {})
    triggers = ("auth", "personal_data", "multi_tenant", "public_internet", "api")
    if not any(conditional.get(k) for k in triggers):
        return
    for doc in ("SECURITY.md", "THREAT-MODEL.md"):
        if not ctx.exists("docs", doc):
            ctx.add("HIGH", "meta/threat-model.md", f"docs/{doc} is required by this capability profile")


# ──────────────────────────── Tier B: forbidden tokens ───────────────────────────

TOKEN_RULES = [
    (".py", r"subprocess\.[a-zA-Z_]+\([^)]*shell\s*=\s*True", "CRIT",
     "cross-stack/security.md", "subprocess with shell=True"),
    (".py", r"yaml\.load\((?![^)]*SafeLoader)", "CRIT",
     "cross-stack/untrusted-input.md", "yaml.load without SafeLoader"),
    (".py", r"\bpickle\.loads?\(", "CRIT",
     "cross-stack/untrusted-input.md", "pickle on possibly-untrusted data"),
    (".py", r"from\s+jose\s+import|import\s+jose\b", "HIGH",
     "cross-stack/auth.md", "python-jose (unmaintained, algorithm-confusion CVEs) — use PyJWT"),
    (".py", r"except\s*:\s*(?:#.*)?$", "MED",
     "cross-stack/error-handling.md", "bare except swallows every error"),
    (".go", r"\bmath/rand\b", "HIGH",
     "cross-stack/security.md", "math/rand is not cryptographically secure"),
    (".tsx", r"dangerouslySetInnerHTML", "HIGH",
     "cross-stack/security.md", "dangerouslySetInnerHTML — sanitize first"),
    (".ts", r"dangerouslySetInnerHTML", "HIGH",
     "cross-stack/security.md", "dangerouslySetInnerHTML — sanitize first"),
    (".ts", r"\bconsole\.log\(", "MED",
     "cross-stack/observability-logging.md", "console.log in shipped code — use the structured logger"),
    (".tsx", r"\bconsole\.log\(", "MED",
     "cross-stack/observability-logging.md", "console.log in shipped code — use the structured logger"),
]

SECRET_PATTERNS = [
    (r"(?i)(api[_-]?key|secret|password|token)\s*[:=]\s*[\"'][A-Za-z0-9/+_-]{16,}[\"']",
     "hardcoded credential literal"),
    (r"AKIA[0-9A-Z]{16}", "AWS access key id"),
    (r"-----BEGIN (?:RSA |EC )?PRIVATE KEY-----", "private key material"),
]


def check_forbidden_tokens(ctx: Context) -> None:
    for suffix, pattern, severity, rule, message in TOKEN_RULES:
        regex = re.compile(pattern, re.MULTILINE)
        for path in ctx.source_files(suffix):
            text = path.read_text(encoding="utf-8", errors="replace")
            for match in regex.finditer(text):
                line_no = text[: match.start()].count("\n") + 1
                ctx.add(severity, rule, message, f"{ctx.rel(path)}:{line_no}")


def check_hardcoded_secrets(ctx: Context) -> None:
    rule = "cross-stack/secrets-management.md"
    for path in ctx.source_files(".py", ".go", ".ts", ".tsx", ".js"):
        text = path.read_text(encoding="utf-8", errors="replace")
        for pattern, message in SECRET_PATTERNS:
            for match in re.finditer(pattern, text):
                line_no = text[: match.start()].count("\n") + 1
                ctx.add("CRIT", rule, message, f"{ctx.rel(path)}:{line_no}")


CHECKS = [
    check_lockfiles, check_env_hygiene, check_env_completeness, check_dockerfiles,
    check_ci_action_pinning, check_framework_pins, check_logging_setup, check_scaffold_matches, check_precommit, check_dependabot, check_migrations,
    check_security_docs, check_forbidden_tokens, check_hardcoded_secrets,
]


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--root", default=".", help="project root (default: cwd)")
    parser.add_argument("--json", action="store_true", help="emit findings as JSON")
    parser.add_argument(
        "--block-on", default="CRIT,HIGH",
        help="severities that fail the run (default: CRIT,HIGH)",
    )
    add_override_arg(parser)
    args = parser.parse_args()

    ctx = Context(root=Path(args.root).resolve())
    for check in CHECKS:
        try:
            check(ctx)
        except Exception as exc:  # a broken check must not mask real findings
            ctx.add("MED", "audit-mechanical.py", f"check {check.__name__} errored: {exc}")

    if args.json:
        print(json.dumps([f.__dict__ for f in ctx.findings], indent=2))
        sys.exit(0)

    blocking = {s.strip().upper() for s in args.block_on.split(",") if s.strip()}
    failures = [f.line() for f in ctx.findings if f.severity in blocking]
    warnings = [f.line() for f in ctx.findings if f.severity not in blocking]

    finish(
        check_name="mechanical convention audit",
        failures=failures,
        warnings=warnings,
        override=args.override,
        ok_message=f"OK — {len(CHECKS)} mechanical checks passed, no {'/'.join(sorted(blocking))} findings.",
    )


if __name__ == "__main__":
    main()
