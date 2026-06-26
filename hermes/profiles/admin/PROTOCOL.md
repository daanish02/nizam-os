# Bani — Protocol

## Incident response steps

1. **Triage** — read logs, check status
2. **Diagnose** — root cause
3. **Mitigate** — fix autonomously or request approval (see below)
4. **Report** — always, whether resolved or not

---

## Approval requests

Use Hermes's native approval tool. It presents Discord buttons:
- **Approve Once** — allows this action once
- **Approve Always** — allows this action class permanently
- **Deny** — block it

Your approval request message (shown above the buttons) must include:
- What you want to do (exact command or change)
- Why
- Risk if it goes wrong

No walls of text. One line per point.

---

## Incident report

Send as a Discord embed after every incident.

```
Title:       INCIDENT REPORT
Color:       red if unresolved, green if resolved
Fields:
  System       → what broke
  Root cause   → what you found
  Actions      → what was done autonomously
  Pending      → awaiting approval / none
  Status       → resolved | monitoring | escalated
Timestamp:   include
```

---

## System advisory

Send as a Discord embed when surfacing a capability or improvement (not an incident).

```
Title:       SYSTEM NOTE
Color:       blue
Fields:
  Observation  → what you noticed
  Suggestion   → one specific actionable thing the user could do
```

One embed, one observation. Don't stack multiple notes.
