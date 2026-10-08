---
type: template
title: Feanor Project Templates Index
description: Index of all output-blueprint templates; read this to find which template an engine should fill when generating docs/PRD.md, docs/ARCHITECTURE.md, docs/specs/, or other project artifacts.
applies_to: [all]
tags: [templates, index]
---

# Feanor Project Templates Catalog

Templates define standard output structures for project artifacts. Feanor agents (`agents/`) read these blueprints when writing documentation into target repositories.

---

## Output Blueprints

- [PRD Template](./prd-template.md) - Product Requirements Document blueprint (`docs/PRD.md`).
- [High-Level Docs](./high-level-docs/index.md) - Selection guide + blueprints for `docs/` (ARCHITECTURE.md always; SCHEMAS/APIS/UI/SECURITY/DEPLOYMENT/RUNBOOK/EXTERNAL-SERVICES/PLAN as needed) plus the 3 Excalidraw diagrams.
- [Spec Template](./spec-template.md) - Interface contract blueprint for API, Database, and Component schemas (`docs/specs/*.md`).
- [README Template](./readme-template.md) - Root `README.md` blueprint written during `/scaffold`. No inline doc/test references — self-contained for humans who want to understand and run the project.
