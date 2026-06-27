# crm-service

Part of [services overview](../services.md). Client, contact, project, pipeline tracking for Arc Systems.

## Tools

| Tool | Description |
|---|---|
| `add_client(name, contact_info, source?)` | Onboard a new client |
| `client_list(status?)` | All clients with status. Redis-cached 15 min. |
| `get_client(client_id)` | Full client record + project history |
| `add_project(client_id, title, value, start_date, deadline)` | Create project |
| `update_project_status(project_id, status, notes?)` | Move project along |
| `add_interaction(client_id, type, notes, date?)` | Log meeting, email, call |
| `pipeline_value()` | Total value of active + pending projects |
| `add_lead(name, contact, source, estimated_value?)` | Add to pipeline |
| `convert_lead(lead_id, client_data)` | Lead → client |
| `open_items(client_id?)` | Pending actions with age |

## Schema (crm)

```
clients(id, name, contact_info, source, status, created_at)
projects(id, client_id, title, value, status, start_date, deadline, created_at)
interactions(id, client_id, type, notes, date, created_at)
leads(id, name, contact, source, estimated_value, status, created_at)
```

DB role: `svc_crm` — see [architecture](../architecture.md#per-service-db-users).
