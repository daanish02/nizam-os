---
type: catalog
title: Cross-Stack Conventions Index
description: Topics that apply uniformly across Go, Python, and TypeScript — api-design, auth, caching, error-handling, module-boundaries, observability, rate-limiting, security, testing, dependency-management; each file has language-specific sections.
applies_to: [all]
tags: [cross-stack, index]
---

# Catalog: conventions/cross-stack

## Document Nodes
* [API Design](./api-design.md) - REST response envelope, cursor-based pagination, error shape, and versioning — apply whenever implementing or reviewing HTTP API endpoints in any backend.
* [Authentication & Authorization](./auth.md) - Token storage, RBAC enforcement, and password rules for Go, Python, and TypeScript — apply whenever implementing auth middleware, route protection, or session handling.
* [Caching](./caching.md) - Cache key format, HTTP caching contract, and invalidation strategy for Go, Python, and TypeScript — apply when implementing application-level or HTTP caching in any layer.
* [Dependency Management](./dependency-management.md) - Lockfile pinning, stdlib-first bias, one package manager per stack, and vulnerability scanning for Go, Python, and TypeScript.
* [Error Handling](./error-handling.md) - Single-handling rule, fail-fast at boundaries, and typed error hierarchies for Go, Python, and TypeScript — apply when implementing error propagation, logging, or API boundary handling in any layer.
* [Module Boundaries & Import Direction](./module-boundaries.md) - Import direction rules, dependency inversion, and cross-domain coupling discipline for Go, Python, and TypeScript.
* [In-App Issue Reporting](./issue-reporting.md) - Optional user-facing bug reporter: capture payload and scrubbing, the abuse surface of a public write endpoint, and the human gate before any fix.
* [Library & Framework Docs](./library-docs.md) - Check version-scoped documentation before implementing against a pinned framework, so code matches the installed version rather than training data.
* [Observability & Logging](./observability-logging.md) - Structured logging rules, log levels, and per-language setup for Go, Python, and TypeScript.
* [Rate Limiting](./rate-limiting.md) - Rate limiting rules at the API boundary for Go and Python; TypeScript rate limiting is covered in security.md.
* [Security](./security.md) - Input validation, injection prevention, secrets handling, and least-privilege rules for Go, Python, and TypeScript.
* [Testing](./testing.md) - Test boundaries, mocking discipline, and TDD loop for Go, Python, and TypeScript.
