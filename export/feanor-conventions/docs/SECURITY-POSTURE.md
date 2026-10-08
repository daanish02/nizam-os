---
type: reference
title: Feanor Security Posture
description: Standing answer to "how secure is this" — Feanor's own attack surface as a tool, and the security properties of the code it produces, mapped to OWASP Top 10 with honest gaps.
applies_to: [maintainer]
tags: [docs, maintainer, security, posture, owasp, compliance]
---

# Security Posture

Two separate questions, often confused:

1. **Is Feanor safe to run?** It executes scripts on developer machines and installs git hooks.
2. **Is the code Feanor produces secure?** This is what a client is actually asking.

Updated by each maintenance audit — history in [AUDIT-LOG.md](./AUDIT-LOG.md).

---

## Part 1 — Feanor's Own Attack Surface

Feanor is a development-time tool with real privileges: it writes files into a repository, installs git hooks, and executes commands.

| Surface | Control |
| :--- | :--- |
| Ticket verification commands | Run **without a shell** via `plan.py verify`; shell operators are rejected at parse time. `docs/plan.toml` is a data file, so executing it as a shell string would make any PR that edits it an execution vector. |
| Completion gate | `plan.py done` refuses without a passing verify on record. The model cannot mark its own work complete. |
| Installation | `lattice add feanor` extracts from a bare clone of the Lattice repo over TLS. No install script is executed in the project. |
| Git hooks | `lattice add` installs `pre-commit-branch-guard`, blocking direct commits to `main`/`qa`. It refuses to overwrite a foreign hook. Local hooks are skippable with `--no-verify`; server-side branch protection is the enforcing layer. |
| Scaffolded output | Generated `start.sh`/`stop.sh` fail loudly rather than silently proceeding on an occupied port. |
| Secrets | `.env` git-ignored; `.env.example` placeholders only; no real credential anywhere in the corpus. |

**Residual risks, accepted:**

- Feanor executes arbitrary project test commands by design. The shell is removed and operators rejected, but `verification_command` still names a binary that runs. A malicious `plan.toml` naming a malicious local binary would run it. Mitigated by treating `plan.toml` as reviewable code in PRs.
- Scaffold scripts run `uv init`, `bunx create-next-app`, and similar, which fetch from public registries. Standard supply-chain exposure for any scaffolding tool; `supply-chain.md` governs what happens afterward.
- `lattice` fetches from a GitHub remote over TLS with no signature verification. Installed hook scripts run on every commit, so a compromised upstream would execute in the project — review `skills/feanor/scripts/pre-commit-branch-guard` after an update, as with any hook.

---

## Part 2 — Security of Generated Code

What the baseline conventions enforce, mapped to OWASP Top 10 (2021). **Enforced** means a convention states the rule and an agent loads it for relevant tickets; it does not mean an automated check proves it in every project.

| OWASP | Covered by | Status |
| :--- | :--- | :--- |
| A01 Broken Access Control | `access-control.md` | Enforced — ownership in the query, deny-by-default routing, tenant scoping, mass-assignment allowlists, mandatory cross-user tests |
| A02 Cryptographic Failures | `security.md`, `data-protection.md`, `auth.md` | Enforced — vetted algorithms, TLS floor, encryption at rest, argon2/bcrypt |
| A03 Injection | `security.md`, `untrusted-input.md` | Enforced — parameterised queries, argv subprocess, auto-escaping, safe deserialization |
| A04 Insecure Design | `meta/threat-model.md`, requirements §2.6 | Enforced — STRIDE per trust boundary, abuse cases traced to controls |
| A05 Security Misconfiguration | `security.md`, `ops/` | Enforced — full security header set, non-root containers, fail-closed |
| A06 Vulnerable Components | `supply-chain.md`, `git/dependabot.md` | Enforced — lockfiles, pinning, scanners in CI |
| A07 Identification & Auth Failures | `auth.md` | Enforced — claim pinning, revocation, lockout, anti-enumeration, MFA for privileged accounts |
| A08 Software & Data Integrity | `supply-chain.md`, `untrusted-input.md` | Enforced — SHA-pinned actions, digest-recorded images, no unsafe deserialization |
| A09 Logging & Monitoring Failures | `observability-logging.md` | **Partial** — logging and redaction enforced; alerting is optional-tier, so a project can opt out of detection |
| A10 SSRF | `untrusted-input.md` | Enforced — allowlist, resolve-then-connect, metadata blocked, redirects re-validated |

### Verification

`/audit` runs `gitleaks`, `govulncheck`/`gosec`, `pip-audit`/`bandit`, `bun audit`, and fails on CRITICAL or HIGH. Control verification against `docs/SECURITY.md` is judgment work, not automated.

### Honest gaps

- **Coverage is by convention, not by proof.** An agent that loads `access-control.md` and still writes an unguarded handler produces a defect the pipeline may not catch. The adversarial-test requirement is the mitigation, and it depends on the planner writing those acceptance criteria.
- **No DAST, no penetration testing** in the pipeline. Static scanning and review only.
- **No automated compliance evidence.** `docs/SECURITY.md` supports a SOC 2 or ISO 27001 conversation; it does not constitute an audit.
- **A09 is partial by design** — see the table above.
- **Three stacks only.** A project outside Go/Python/TypeScript gets cross-stack rules with no language-specific enforcement.

### What can honestly be claimed to a client

> Every project applies a mandatory security baseline covering the OWASP Top 10: access control with object-level ownership checks, input validation including SSRF and upload handling, secrets management with scanning in pre-commit and CI, dependency pinning and vulnerability scanning, and structured logging with PII redaction. Systems handling personal data additionally receive a documented threat model, a data classification and retention inventory, and a security control document. Every build runs secret, dependency, and static analysis scanning, and a critical or high finding fails the audit.

Do not claim certification, penetration testing, or continuous runtime monitoring. None of those are in scope.
