---
type: template
title: EXTERNAL-SERVICES.md Template
description: Blueprint for docs/EXTERNAL-SERVICES.md — catalogs every third-party service dependency, its role, auth method, and failure behavior for projects with significant external integrations.
applies_to: [hld]
tags: [template, external-services]
---

# External Services

> **Project:** {{PROJECT_NAME}}

## {{SERVICE_NAME}}

- **Used for:** {{PURPOSE}}
- **Integration point:** {{WHERE_IN_CODEBASE}}
- **Failure behavior:** {{WHAT_HAPPENS_IF_SERVICE_IS_DOWN}}
- **Cost/rate limits:** {{RELEVANT_CONSTRAINTS}}
