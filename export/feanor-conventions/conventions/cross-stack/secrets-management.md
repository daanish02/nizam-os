---
type: convention
title: Secrets Management
description: Where secrets live, how they reach a process, rotation policy, and secret scanning in pre-commit and CI — applies to Go, Python, and TypeScript projects equally.
applies_to: [go, python, typescript, ops]
tags: [secrets, credentials, rotation, gitleaks, env-vars, security, owasp-a05]
---

# Secrets Management

`security.md` says "no secrets in code or logs". This file says where they go instead, and how a leak is caught before it ships.

## Cross-Stack Rules

- **A secret never enters git.** Not in source, not in a config file, not in a test fixture, not in a commit message, not in a `.md` example. Once pushed, it is compromised — rotate it; deleting the commit does not un-leak it.
- **`.env` is git-ignored; `.env.example` is committed** with every key present and every value a placeholder (`{{DATABASE_URL}}`). The example file is the contract for what a service needs; a missing key there is a deployment failure later.
- **Production secrets do not come from `.env` files.** Use the platform's secret store — AWS Secrets Manager / SSM Parameter Store, GCP Secret Manager, Azure Key Vault, Vault, or the host platform's encrypted environment settings. `.env` is a local-development convenience only.
- **Read every secret once, at startup, through the config module.** No `os.getenv` / `os.Getenv` / `process.env` scattered through the codebase. A missing required secret fails at startup, loudly, not at the first request that needs it. See each language's `project-layout.md` for the config module.
- **Never log a secret, and never log the whole config object.** Config types get an explicit redacting formatter — see `observability-logging.md`.
- **Never put a secret in a URL, a query string, or a path.** They land in access logs, proxy logs, browser history, and `Referer` headers.
- **Never send a secret to the client.** In Next.js this means never prefixing one with `NEXT_PUBLIC_`: that value is inlined into the JavaScript bundle at build time, is permanent in every deployed copy, and is readable by anyone who opens the page.
- **Distinct secrets per environment.** A staging credential that also works in production makes staging a production breach.
- **Least privilege per secret.** A service gets a credential scoped to what it does, not a shared admin key.

## Rotation

- Every secret has a documented owner, storage location, and rotation interval in `docs/SECURITY.md`. A secret nobody owns never gets rotated.
- Rotate on a schedule, and immediately on any suspected exposure or when someone with access leaves.
- **Design for rotation before you need it**: support two valid signing keys at once (key id in the JWT header, per `auth.md`), so rotation is a rollout rather than an outage.
- Prefer short-lived, automatically-issued credentials (workload identity, IAM roles, OIDC federation from CI) over long-lived static keys. A credential that expires in an hour is a smaller incident than one that lasts a year.
- **CI authenticates to cloud providers via OIDC, not a stored access key**, wherever the provider supports it.

## Scanning

Secret scanning runs in two places — locally so a secret never reaches a commit, and in CI so a bypassed hook is still caught.

- **Pre-commit:** `gitleaks` runs on staged changes. Configured in `.pre-commit-config.yaml` — see `git/pre-commit-hooks.md`.
- **CI:** the same scan runs on every pull request over the full diff range, and the job is required. A hook can be skipped with `--no-verify`; a required check cannot.
- **Enable the host's own push protection** (GitHub secret scanning with push protection) as the third layer — see `git/github-repo-setup.md`.
- A scanner finding is treated as a real leak until proven otherwise: rotate first, then investigate.
- Suppressions are per-finding with a written reason, never a blanket path exclusion.

```yaml
# .pre-commit-config.yaml — pinned rev, per supply-chain.md
- repo: https://github.com/gitleaks/gitleaks
  rev: v8.28.0
  hooks:
    - id: gitleaks
```

## CI Secrets

- Secrets reach CI jobs as masked environment variables or via OIDC — never as command-line arguments, which appear in process listings and in the job log.
- **Never `echo` a secret**, and do not run a shell in trace mode (`set -x`) in a job that has one in its environment.
- Workflows triggered by forked pull requests must not have access to production secrets. Use the trigger that runs without them.
- Third-party CI actions get access to whatever the job holds — see `supply-chain.md` for pinning them by commit SHA.

## Incident Response

When a secret is exposed, in this order:

1. **Rotate the credential.** Before investigating, before writing anything up. The old value is compromised the moment it was exposed.
2. **Revoke the old value** at the provider so it cannot be used during the changeover.
3. **Check the access logs** for use of the old credential, back to the point of exposure.
4. **Remove the value** from wherever it leaked, and record the incident in `docs/SECURITY.md`'s accepted-risk / incident log.
5. **Fix the path that let it through** — the missing scan, the logged config object, the hard-coded fallback.

Never step 4 before step 1: rewriting history is slow and public, and the credential is live the whole time.

Related: `data-protection.md` (what the secrets protect), `supply-chain.md` (pinning), `observability-logging.md` (redaction), `git/pre-commit-hooks.md` (hook wiring), `auth.md` (signing key rotation).
