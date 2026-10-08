---
type: catalog
title: Feanor Micro-Standards & Conventions Index
description: Technical pattern blueprints, framework conventions, and language standards enforced by Feanor execution agents.
applies_to: [all]
tags: [conventions, index]
---

# Feanor Technical Conventions & Micro-Standards

This directory defines non-negotiable architectural patterns and execution standards across tech stack layers. Feanor agents (`agents/`) enforce these guidelines during system planning and code generation.

---

## Technology Subdirectories

- [python/](./python/index.md) - Python 3.12, `uv` workspace layout, async/concurrency, typing, naming micro-standards (backend only). Language-specific only; cross-stack topics live in `cross-stack/`.
- [go/](./go/index.md) - Go modules, layout, concurrency/context, and database standards (backend only). Language-specific only; cross-stack topics live in `cross-stack/`.
- [nextjs/](./nextjs/index.md) - Next.js/Bun, App Router, components/data, styling, and performance (frontend only). React/Next.js-specific only; TypeScript language rules live in `typescript/`, cross-stack topics live in `cross-stack/`.
- [typescript/](./typescript/index.md) - TypeScript language-level rules for all TS projects: type system, module system, code style, and tooling.
- [cross-stack/](./cross-stack/) - Topics that apply across all languages and stacks: api-design, auth, caching, code-comments, database (RDBMS-agnostic), db-connection (backend-to-DB layer), dependency-management, error-handling, health-endpoints, middleware (HTTP stack + execution order), module-boundaries, observability-logging, rate-limiting, testing — plus the security set below.
- **Security set** (all in `cross-stack/`, entry point is `security.md`):
  - [security.md](./cross-stack/security.md) - Injection, cryptography, security response headers, least privilege.
  - [access-control.md](./cross-stack/access-control.md) - Object ownership and IDOR, deny-by-default routing, tenant scoping, mass assignment. Required for any ticket touching a route handler.
  - [untrusted-input.md](./cross-stack/untrusted-input.md) - SSRF, file upload, unsafe deserialization, path traversal.
  - [secrets-management.md](./cross-stack/secrets-management.md) - Secret storage, rotation, scanning in pre-commit and CI, incident response.
  - [data-protection.md](./cross-stack/data-protection.md) - Classification tiers, PII inventory, encryption, retention and deletion.
  - [supply-chain.md](./cross-stack/supply-chain.md) - Lockfile integrity, dependency vetting, pinning images and CI actions, SBOM.
- [git/](./git/index.md) - Branch strategy, commit format, pre-commit hooks, test tiers, Dependabot.
- [ops/](./ops/index.md) - Dockerfile + `.dockerignore` per stack, stored in `backend/`/`frontend/`.
- [databases/](./databases/index.md) - RDBMS dialect-specific rules (PostgreSQL, MySQL, MariaDB, SQL Server, Oracle, SQLite). Always loaded alongside `cross-stack/database.md`.
- [coding-principles.md](./coding-principles.md) - Universal design principles across all stacks: composition, dependency inversion, thin layers, pure logic, readability, and when to abstract.
- [tdd.md](./tdd.md) - TDD loop discipline (red-green-refactor), seams, vertical slicing, tautological test anti-pattern, and mocking rules — applied across all stacks.

Add a new subdirectory here only once it's actually written, following `workflows/maintain-repo.md` §3 — a link to a directory that doesn't exist yet is worse than no link.
