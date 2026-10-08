---
type: convention
title: Supply Chain Security
description: Lockfile integrity, dependency vetting, pinning base images and CI actions, and SBOM generation — load for any ticket that adds a dependency, edits a Dockerfile, or changes a CI workflow.
applies_to: [go, python, typescript, ops]
tags: [supply-chain, dependencies, pinning, sbom, lockfile, ci, docker, security, owasp-a06, owasp-a08]
---

# Supply Chain Security

Most code in a shipped system was written by someone else. These rules govern what gets in and whether the build that ships is the build that was reviewed.

## Lockfiles

- **A lockfile is committed for every project and is never edited by hand**: `uv.lock`, `go.sum`, `bun.lock` (or the older binary `bun.lockb`) / `package-lock.json`.
- **CI installs from the lockfile in frozen mode** and fails if it is out of date — `uv sync --frozen`, `go mod verify`, `bun install --frozen-lockfile`. An install that silently resolves a newer version means CI tested something other than what ships.
- A lockfile change in a pull request is reviewed like code. An unexplained diff there is the single highest-signal indicator of a compromised or typosquatted dependency.
- Never disable integrity/hash checking to make an install succeed.

## Adding a Dependency

Adding a dependency is a decision, not a reflex. Before adding one, confirm:

- **The standard library or an existing dependency does not already do it.** See `dependency-management.md`.
- **It is actively maintained** — a release or meaningful commit within roughly the last year, and open security issues addressed.
- **The name is right.** Typosquatting works because the wrong name installs cleanly. Check the exact package name against the project's own documentation, not a search result or an LLM's memory.
- **It is widely used**, or the code has been read. A package with very few users is code you are adopting, not depending on.
- **The licence is acceptable** for the project's distribution model. Copyleft in a proprietary product is a legal problem, not a technical one.
- **Its own dependency tree is not disproportionate.** A one-function package that pulls forty transitive dependencies is a bad trade.
- Prefer a well-maintained package over a hand-rolled implementation for anything security-sensitive (crypto, JWT, HTML sanitisation, password hashing). Prefer the standard library over a package for anything trivial.

## Vulnerability Scanning

- Runs in CI on every pull request and on a schedule (a dependency becomes vulnerable without your code changing): `govulncheck ./...`, `uv run pip-audit`, `bun audit`.
- Dependabot is configured per `git/dependabot.md`. Security updates are merged promptly; version bumps are batched.
- A finding is triaged, not ignored. If it is not exploitable in this context, record why in the pull request — do not silently suppress it.
- Enable the host's dependency-review gate on pull requests so a newly-introduced vulnerable version is blocked before merge, not reported after.

## Pinning

Floating tags mean the build is not reproducible and a compromised upstream reaches production without any change on your side.

- **Base images: pin the minor version, and record the digest in a comment.**

  ```dockerfile
  # python:3.12-slim  digest as of 2026-09-07:
  # sha256:0000000000000000000000000000000000000000000000000000000000000000
  FROM python:3.12-slim AS runtime
  ```

  Never `:latest`. This applies to every stage of a multi-stage build and to images copied from (`COPY --from=ghcr.io/astral-sh/uv:0.12.0`), which are just as much a build input.

- **CI actions: pin third-party actions to a full commit SHA**, not a tag. A tag is mutable and can be repointed at new code by whoever controls the repository:

  ```yaml
  - uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
  ```

  Keep the version in a trailing comment so the pin is readable and Dependabot can update it.

- **Pre-commit hooks: pin `rev` to a tag or SHA**, never a moving branch. See `git/pre-commit-hooks.md`.
- **Tool versions are pinned** in CI and documented: `uv` minor-locked, Go toolchain version in `go.mod`, Bun version in `.bun-version`.

## Build Integrity

- **Grant CI the least privilege it needs.** Default the workflow token to read-only and elevate per job. A build job does not need write access to the repository.
- **Never run untrusted code with secrets in scope.** A workflow triggered by a forked pull request must not hold production credentials — see `secrets-management.md`.
- **Do not `curl … | bash` in a build.** Download to a file, verify a checksum or signature, then execute. A pipe executes whatever the URL returns at that moment, unreviewed.
- Builds are reproducible from a clean checkout: no step depends on a file that exists only on a developer machine.
- **Generate an SBOM** (CycloneDX or SPDX) as a release artifact for anything shipped to an enterprise client — increasingly a procurement requirement, and the only fast way to answer "are you affected by X?" when the next widely-exploited CVE lands.
- **Do not publish secrets into image layers.** A secret `COPY`d in and deleted in a later layer is still in the image. Use build secrets or runtime injection — see `ops/` Dockerfile conventions.

Related: `dependency-management.md` (per-language tooling), `secrets-management.md` (CI credentials), `git/dependabot.md`, `git/pre-commit-hooks.md`, `ops/index.md` (Dockerfiles).
