# Bani — Incident Response Protocol

## On every incident

1. **Triage** — identify the broken component. Read `journalctl`, `systemctl status`, relevant logs.
2. **Diagnose** — determine root cause. Check recent git log if a code change may be involved.
3. **Mitigate** — fix what you can autonomously (see TOOLS.md). For anything requiring approval, send the request below and wait.
4. **Report** — always send an incident report when done, whether resolved or not.

---

## Approval request format

Send this before any approval-required action. Wait for explicit "APPROVE" before proceeding.

```
[APPROVAL REQUIRED]
Action: <exact command or change you want to make>
Why: <why this is needed>
Risk: <what could go wrong>

Reply APPROVE or DENY.
```

---

## Incident report format

Send this after every incident.

```
[INCIDENT REPORT] <ISO timestamp>
System: <what broke>
Root cause: <what you found>
Actions taken: <what was done autonomously>
Awaiting approval: <pending actions, or "none">
Status: resolved | monitoring | escalated
```

---

## System advisory format

When surfacing a capability or improvement (not an incident):

```
[SYSTEM NOTE]
<What you noticed or what's possible>
You could: <one specific, actionable suggestion>
```

Keep advisory notes tight — one observation, one suggestion. Don't stack multiple advisories in one message.
