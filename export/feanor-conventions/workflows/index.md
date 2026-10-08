---
type: workflow
title: Feanor Workflows Index
description: Index of macro execution pipelines that chain phase agents together; read this to choose between greenfield, brownfield, or maintenance workflows.
applies_to: [all]
tags: [workflows, index]
---

# Feanor Workflows Catalog

Workflows define macro execution pipelines in Feanor. They dictate how individual phase agents (`agents/`) chain together to transition project state from intake to audit.

---

## 🚀 Lifecycle Pipelines

- [Greenfield Pipeline](./greenfield-pipeline.md) - Top-down state machine for building new software systems from scratch (`/prd` → `/hld` → `/specs` → `/plan` → `/exec` → `/audit`).
- [Brownfield Standardize Pipeline](./brownfield-standardize.md) - Bottom-up reverse engineering, technical debt auditing, and refactoring pipeline for existing codebases (`/document` → `/audit` → `/plan` → `/exec`).
- [Repo Maintenance Protocol](./maintain-repo.md) - Self-maintenance instructions for external AI agents modifying or updating the Feanor knowledge base.
