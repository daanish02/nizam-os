---
type: template
title: DEPLOYMENT.md Template
description: Blueprint for docs/DEPLOYMENT.md — documents environments, infrastructure dependencies, CI/CD pipeline, and release steps for projects with non-trivial deployment concerns.
applies_to: [hld, deployment]
tags: [template, deployment, infra]
---

# Deployment

> **Project:** {{PROJECT_NAME}}

## Environments

| Environment  | Branch     | Purpose     |
| :----------- | :--------- | :---------- |
| {{ENV_NAME}} | {{BRANCH}} | {{PURPOSE}} |

## Infra Dependencies

- {{INFRA_ITEM}} — {{PURPOSE}}

## Release Process

```mermaid
flowchart LR
    Merge[Merge to {{BRANCH}}] --> Build[Build] --> Deploy[Deploy to {{ENV}}]
```

- **Rollback:** {{ROLLBACK_PROCEDURE}}
