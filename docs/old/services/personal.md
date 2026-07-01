# personal-service

Part of [services overview](../services.md). Goals, tasks, habits, daily notes.

## Tools

| Tool | Description |
|---|---|
| `add_goal(title, description, deadline, area?)` | Create a goal |
| `list_goals(area?, status?)` | Active goals with linked tasks |
| `add_task(title, goal_id?, due_date?, effort?)` | Add a task |
| `complete_task(task_id)` | Mark done, log completion time |
| `today_tasks()` | Tasks due today or overdue |
| `log_habit(habit_name, date?, notes?)` | Record habit completion |
| `habit_streak(habit_name)` | Current and best streak. Cached until next log. |
| `habits_today()` | All habits with today's status |
| `add_note(content, tags?)` | Append to daily journal |
| `morning_brief()` | Habits today, budget status, overdue tasks, top goal |

## Schema (personal)

```
goals(id, title, description, area, status, deadline, created_at)
tasks(id, goal_id, title, effort, status, due_date, completed_at)
habits(id, name, frequency, created_at)
habit_log(id, habit_id, date, notes)
notes(id, content, tags, created_at)
```

DB role: `svc_personal` — see [architecture](../architecture.md#per-service-db-users).
