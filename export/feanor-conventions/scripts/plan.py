# /// script
# requires-python = ">=3.12"
# dependencies = ["tomlkit", "rich"]
# ///
"""Plan manager for docs/plan.toml.

Usage (from project root):
  uv run feanor/scripts/plan.py status            # rich table of all tickets
  uv run feanor/scripts/plan.py next              # next unblocked todo ticket
  uv run feanor/scripts/plan.py start  TICK-001   # mark in-progress
  uv run feanor/scripts/plan.py verify TICK-001   # run verification_command, record real exit code
  uv run feanor/scripts/plan.py done   TICK-001   # mark done (requires a passing verify)
  uv run feanor/scripts/plan.py block  TICK-001 "reason"   # mark blocked
  uv run feanor/scripts/plan.py check             # verify plan integrity

`verify` is the gate: it is the only thing that sets tests_passing = true, and `done`
refuses to run without it. The command is executed without a shell, so a
verification_command is a plain argv line — put any directory change in the ticket's
working_dir field, not in the command.
"""

import shlex
import subprocess
import sys
import tomllib
from datetime import datetime, timezone
from pathlib import Path

try:
    import tomlkit
    from rich import box
    from rich.console import Console
    from rich.table import Table
except ModuleNotFoundError:
    from _gate import require_uv_run

    require_uv_run("tomlkit, rich")

PLAN_PATH = Path("docs/plan.toml")
LOG_PATH = Path(".feanor/logs/validation.log")
STATUS_STYLE = {
    "todo":        "white",
    "in-progress": "yellow",
    "done":        "green",
    "blocked":     "red",
}

console = Console()


def validate_command(raw: str) -> list[str]:
    """Parse a verification_command into argv, or raise ValueError explaining why not.

    The command is run with shell=False, so an unquoted shell operator would be
    silently inert rather than doing what the ticket appears to say. Reject those.
    A metacharacter *inside* a quoted argument is an ordinary character and is fine
    (`python -c "import sys; sys.exit(1)"`), which is why this inspects the parsed
    tokens rather than the raw string.
    """
    if not raw.strip():
        raise ValueError("verification_command is empty")

    lexer = shlex.shlex(raw, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    try:
        tokens = list(lexer)
    except ValueError as exc:  # unbalanced quotes
        raise ValueError(f"verification_command is not parseable: {exc}") from exc

    operators = set(";&|<>()")
    for token in tokens:
        if token and set(token) <= operators:
            raise ValueError(
                f"verification_command contains the shell operator {token!r}. It runs "
                f"without a shell, so the operator would not do what it looks like it "
                f"does — put any directory change in the ticket's working_dir field, and "
                f"split two commands into two tickets or a script under scripts/."
            )
    if not tokens:
        raise ValueError("verification_command parsed to no arguments")
    return tokens


def load(path: Path = PLAN_PATH) -> tomlkit.TOMLDocument:
    if not path.exists():
        console.print(f"[red]Not found:[/] {path}  —  run /plan first")
        sys.exit(1)
    return tomlkit.parse(path.read_text(encoding="utf-8"))


def save(doc: tomlkit.TOMLDocument, path: Path = PLAN_PATH) -> None:
    path.write_text(tomlkit.dumps(doc), encoding="utf-8")


def cmd_status(doc: tomlkit.TOMLDocument) -> None:
    tickets = doc.get("tickets", [])
    meta = doc.get("meta", {})
    total = len(tickets)
    done_count = sum(1 for t in tickets if t["status"] == "done")

    table = Table(
        title=f"[bold]{meta.get('project', 'Plan')}[/]  —  {done_count}/{total} done",
        box=box.ROUNDED,
        show_lines=True,
    )
    table.add_column("ID", style="dim", no_wrap=True)
    table.add_column("Title")
    table.add_column("Status", no_wrap=True)
    table.add_column("Tests", no_wrap=True)
    table.add_column("Blocked by", no_wrap=True)

    for t in tickets:
        status = t.get("status", "todo")
        style = STATUS_STYLE.get(status, "white")
        tests = "[green]✓[/]" if t.get("tests_passing") else "[dim]—[/]"
        blocked = t.get("blocked_by", "") or ""
        table.add_row(
            t["id"],
            t["title"],
            f"[{style}]{status}[/]",
            tests,
            blocked,
        )

    console.print(table)


REQUIRED_FIELDS = (
    "id", "title", "status", "description", "acceptance_criteria",
    "target_files", "convention_tags", "verification_command", "depends_on",
)
CODE_EXTENSIONS = (".py", ".go", ".ts", ".tsx", ".js")
TEST_MARKERS = ("test", "spec", "_test.go")
# Paths where a request enters the system. A ticket touching one of these is
# making an authorization decision whether or not its author noticed, and a
# passing test suite looks identical with and without the ownership check.
HANDLER_MARKERS = (
    "router", "handler", "controller", "routes", "route",
    "actions", "resolver", "endpoint", "views", "/api/",
)


def known_tags() -> set[str]:
    """Every canonical tag and alias in conventions/tags.toml."""
    tags_path = Path(__file__).resolve().parent.parent / "conventions" / "tags.toml"
    if not tags_path.exists():
        return set()
    with tags_path.open("rb") as f:
        tags = tomllib.load(f).get("tags", {})
    names: set[str] = set()
    for canonical, entry in tags.items():
        names.add(canonical)
        names.update(entry.get("aliases", []))
    return names


def _tag_is_known(tag: str, vocabulary: set[str]) -> bool:
    if not vocabulary or tag in vocabulary:
        return True
    # Language-qualified forms resolve to the base tag — see resolve-context.py.
    for prefix in ("go-", "python-", "nextjs-", "typescript-", "ts-"):
        if tag.startswith(prefix) and tag[len(prefix):] in vocabulary:
            return True
    return False


def validate_ticket(t: dict, all_ids: set[str], vocabulary: set[str]) -> list[str]:
    """Structural problems that make a ticket unsafe to execute.

    An under-specified ticket does not fail loudly — the agent simply builds
    less than intended, and nothing reports it. That is why this blocks.
    """
    tid = t.get("id", "<no id>")
    issues: list[str] = []

    for field in REQUIRED_FIELDS:
        if field not in t:
            issues.append(f"{tid}: missing required field '{field}'")
        elif t[field] in ("", None):
            issues.append(f"{tid}: field '{field}' is empty")

    targets = list(t.get("target_files") or [])
    tags = [str(x) for x in (t.get("convention_tags") or [])]
    criteria = list(t.get("acceptance_criteria") or [])

    for tag in tags:
        if not _tag_is_known(tag, vocabulary):
            issues.append(
                f"{tid}: convention_tag '{tag}' is not in conventions/tags.toml — "
                f"those rules would be silently absent at execution"
            )

    if not criteria:
        issues.append(f"{tid}: acceptance_criteria is empty — nothing defines 'done'")

    produces_code = any(str(p).endswith(CODE_EXTENSIONS) for p in targets)
    if produces_code:
        if not any(any(m in str(p).lower() for m in TEST_MARKERS) for p in targets):
            issues.append(
                f"{tid}: code ticket lists no test file in target_files — "
                f"tdd.md makes a failing test first mandatory"
            )
        for required in ("coding-principles", "tdd"):
            if required not in tags:
                issues.append(f"{tid}: code ticket missing mandatory tag '{required}'")
        if not any(t_ in tags for t_ in ("boundaries", "python-boundaries", "go-boundaries", "nextjs-boundaries")):
            issues.append(f"{tid}: code ticket missing a module-boundaries tag")

        # Lint must run per ticket, not only at pre-push. A bare test command
        # lets a lint error survive every ticket in between — which is what a
        # live run did. verification_command is a single shell-free command by
        # design (D-005), so the only way to run both is the project's own
        # check script.
        command = str(t.get("verification_command", ""))
        runs_lint = any(
            marker in command
            for marker in ("check.sh", "ruff", "biome", "golangci-lint", "go vet", "eslint")
        )
        if not runs_lint:
            issues.append(
                f"{tid}: verification_command runs tests but not lint — "
                f"use 'bash scripts/check.sh' so a lint error fails the ticket, "
                f"not the push"
            )

    if any(any(m in str(p).lower() for m in HANDLER_MARKERS) for p in targets):
        if "access-control" not in tags:
            issues.append(
                f"{tid}: touches a request entry point but lacks the 'access-control' tag "
                f"— missing authorization is invisible in a passing test suite"
            )

    spec_ref = str(t.get("spec_ref") or "")
    if spec_ref:
        spec_file = Path(spec_ref.split("#", 1)[0])
        if not spec_file.exists():
            issues.append(f"{tid}: spec_ref points at missing file '{spec_file}'")

    for dep in t.get("depends_on") or []:
        dep_id = dep.get("id") if isinstance(dep, dict) else dep
        if dep_id not in all_ids:
            issues.append(f"{tid}: depends_on unknown ticket '{dep_id}'")
        if not (isinstance(dep, dict) and dep.get("reason")):
            issues.append(f"{tid}: depends_on '{dep_id}' has no reason")

    workdir = str(t.get("working_dir") or ".")
    if not Path(workdir).is_dir():
        issues.append(f"{tid}: working_dir '{workdir}' does not exist")

    try:
        validate_command(str(t.get("verification_command", "")))
    except ValueError as exc:
        issues.append(f"{tid}: {exc}")

    return issues


def find_dependency_cycles(tickets: list) -> list[str]:
    graph = {
        t["id"]: [d.get("id") if isinstance(d, dict) else d for d in (t.get("depends_on") or [])]
        for t in tickets if "id" in t
    }
    issues, state = [], {}

    def visit(node: str, path: list[str]) -> None:
        if state.get(node) == "done":
            return
        if state.get(node) == "visiting":
            cycle = " -> ".join(path[path.index(node):] + [node])
            issues.append(f"dependency cycle: {cycle}")
            return
        state[node] = "visiting"
        for nxt in graph.get(node, []):
            if nxt in graph:
                visit(nxt, path + [node])
        state[node] = "done"

    for node in graph:
        visit(node, [])
    return issues


def cmd_next(doc: tomlkit.TOMLDocument) -> None:
    tickets = doc.get("tickets", [])
    all_ids = {t["id"] for t in tickets if "id" in t}
    done_ids = {t["id"] for t in tickets if t.get("status") == "done"}
    vocabulary = known_tags()

    for t in tickets:
        if t.get("status") != "todo":
            continue
        deps = {d.get("id") if isinstance(d, dict) else d for d in (t.get("depends_on") or [])}
        if deps - done_ids:
            continue

        issues = validate_ticket(t, all_ids, vocabulary)
        if issues:
            # Refuse to hand out a ticket that cannot be executed faithfully.
            console.print(f"[red]BLOCKED — {t.get('id', '?')} fails validation:[/]")
            for issue in issues:
                console.print(f"  {issue}")
            console.print(
                "\nFix the ticket in docs/plan.toml and re-run. "
                "Executing it as-is would silently build less than the plan intends."
            )
            sys.exit(1)

        console.print(f"[bold]{t['id']}[/]  {t['title']}")
        console.print(f"  [dim]{t['description'].strip()[:120]}[/]")
        return

    console.print("[green]All tickets complete or blocked.[/]")


def _find_ticket(doc: tomlkit.TOMLDocument, ticket_id: str):
    for t in doc.get("tickets", []):
        if t["id"] == ticket_id:
            return t
    return None


def cmd_start(doc: tomlkit.TOMLDocument, ticket_id: str) -> None:
    t = _find_ticket(doc, ticket_id)
    if t is None:
        console.print(f"[red]Ticket {ticket_id} not found.[/]")
        sys.exit(1)
    t["status"] = "in-progress"
    save(doc)
    console.print(f"[yellow]in-progress[/]  {ticket_id}")


def cmd_verify(doc: tomlkit.TOMLDocument, ticket_id: str) -> None:
    """Run the ticket's verification_command and record its real exit code.

    This is the quality gate. It records the exit status of the command itself —
    not of a downstream pipe — and is the only thing that sets tests_passing.
    """
    t = _find_ticket(doc, ticket_id)
    if t is None:
        console.print(f"[red]Ticket {ticket_id} not found.[/]")
        sys.exit(1)

    raw = str(t.get("verification_command", ""))
    try:
        argv = validate_command(raw)
    except ValueError as exc:
        console.print(f"[red]{ticket_id}: {exc}[/]")
        sys.exit(1)

    workdir = Path(str(t.get("working_dir") or "."))
    if not workdir.is_dir():
        console.print(f"[red]{ticket_id}: working_dir does not exist:[/] {workdir}")
        sys.exit(1)

    try:
        proc = subprocess.run(argv, cwd=workdir, capture_output=True, text=True)
        output, exit_code = proc.stdout + proc.stderr, proc.returncode
    except OSError as exc:
        output, exit_code = f"failed to execute {argv[0]!r}: {exc}\n", 127

    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with LOG_PATH.open("a", encoding="utf-8") as log:
        log.write(f"\n=== {ticket_id} @ {datetime.now(timezone.utc).isoformat()} ===\n")
        log.write(f"$ {raw}   (cwd={workdir})\n")
        log.write(output)
        log.write(f"exit_code={exit_code}\n")

    sys.stdout.write(output)
    sys.stdout.flush()

    t["tests_passing"] = exit_code == 0
    save(doc)

    if exit_code != 0:
        console.print(f"[red]verification failed[/]  {ticket_id}  —  exit_code={exit_code}")
        sys.exit(exit_code)
    console.print(f"[green]verified[/]  {ticket_id}  —  exit_code=0")


def cmd_done(doc: tomlkit.TOMLDocument, ticket_id: str) -> None:
    t = _find_ticket(doc, ticket_id)
    if t is None:
        console.print(f"[red]Ticket {ticket_id} not found.[/]")
        sys.exit(1)
    if not t.get("tests_passing"):
        console.print(
            f"[red]Refusing to mark {ticket_id} done:[/] no passing verification on record.\n"
            f"  Run: uv run feanor/scripts/plan.py verify {ticket_id}"
        )
        sys.exit(1)
    t["status"] = "done"
    save(doc)
    console.print(f"[green]done[/]  {ticket_id}")


def cmd_block(doc: tomlkit.TOMLDocument, ticket_id: str, reason: str) -> None:
    t = _find_ticket(doc, ticket_id)
    if t is None:
        console.print(f"[red]Ticket {ticket_id} not found.[/]")
        sys.exit(1)
    t["status"] = "blocked"
    t["blocked_by"] = reason
    save(doc)
    console.print(f"[red]blocked[/]  {ticket_id}  —  {reason}")


def cmd_check(doc: tomlkit.TOMLDocument) -> None:
    tickets = doc.get("tickets", [])
    all_ids = {t["id"] for t in tickets if "id" in t}
    vocabulary = known_tags()

    issues = []
    for t in tickets:
        if t.get("status") == "done" and not t.get("tests_passing"):
            issues.append(f"  {t['id']} marked done but tests_passing = false")
        issues.extend(f"  {problem}" for problem in validate_ticket(t, all_ids, vocabulary))
    issues.extend(f"  {problem}" for problem in find_dependency_cycles(tickets))
    if issues:
        console.print("[red]Integrity issues:[/]")
        for i in issues:
            console.print(i)
        sys.exit(1)
    else:
        console.print("[green]Plan OK — no integrity issues.[/]")


def main() -> None:
    args = sys.argv[1:]
    if not args:
        console.print("Usage: plan.py <status|next|start|verify|done|block|check> [args]")
        sys.exit(1)

    doc = load()
    cmd = args[0]

    if cmd == "status":
        cmd_status(doc)
    elif cmd == "next":
        cmd_next(doc)
    elif cmd == "start":
        if len(args) < 2:
            console.print("[red]start requires ticket id[/]")
            sys.exit(1)
        cmd_start(doc, args[1])
    elif cmd == "verify":
        if len(args) < 2:
            console.print("[red]verify requires ticket id[/]")
            sys.exit(1)
        cmd_verify(doc, args[1])
    elif cmd == "done":
        if len(args) < 2:
            console.print("[red]done requires ticket id[/]")
            sys.exit(1)
        cmd_done(doc, args[1])
    elif cmd == "block":
        if len(args) < 3:
            console.print("[red]block requires ticket id and reason[/]")
            sys.exit(1)
        cmd_block(doc, args[1], args[2])
    elif cmd == "check":
        cmd_check(doc)
    else:
        console.print(f"[red]Unknown command:[/] {cmd}")
        sys.exit(1)


if __name__ == "__main__":
    main()
