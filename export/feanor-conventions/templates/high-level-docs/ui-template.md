---
type: template
title: UI.md Template
description: Blueprint for docs/UI.md — documents screen flows, key states, and interaction patterns for projects with a non-trivial user interface.
applies_to: [hld, ui]
tags: [template, ui]
---

# UI

> **Project:** {{PROJECT_NAME}}

## {{FLOW_NAME}}

```mermaid
flowchart LR
    A[{{STATE_1}}] --> B[{{STATE_2}}] --> C[{{OUTCOME}}]
```

- **Entry point:** {{HOW_USER_GETS_HERE}}
- **Key states:** {{STATES_AND_TRANSITIONS}}
- **Edge cases:** {{ERROR_OR_EMPTY_STATES}}
