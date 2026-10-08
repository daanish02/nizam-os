---
type: template
title: SCHEMAS.md Template
description: Blueprint for docs/SCHEMAS.md — documents database tables, collections, or key data structures for projects where the persistence layer is complex enough to warrant a dedicated reference.
applies_to: [hld, schemas]
tags: [template, schemas, data]
---

# Schemas

> **Project:** {{PROJECT_NAME}}

## {{TABLE_OR_COLLECTION_NAME}}

| Field     | Type     | Constraints    | Notes    |
| :-------- | :------- | :------------- | :------- |
| {{FIELD}} | {{TYPE}} | {{CONSTRAINT}} | {{NOTE}} |

**Relations:** {{FOREIGN_KEYS_OR_REFERENCES}}
**Indexes:** {{INDEXES_AND_WHY}}
