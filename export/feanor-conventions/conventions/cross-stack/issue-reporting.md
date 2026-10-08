---
type: convention
title: In-App Issue Reporting
description: Rules for a user-facing bug reporter that captures page context and opens a tracker issue, covering the capture payload, the abuse surface of a public write endpoint, and the human gate before any fix.
applies_to: [nextjs, python, go]
tags: [issue-reporting, feedback]
---

# In-App Issue Reporting

An optional capability: a widget where a user reports a problem on the page they are looking at, and the backend opens an issue in the tracker with the context already attached. It replaces "the thing looked wrong yesterday" with a reproducible report.

Optional because it carries real ongoing cost — a public write path, an API token, and a stream of issues someone has to triage. See `docs/CAPABILITIES.md`.

## The Flow

1. The user clicks **Report an issue**, then selects the element that is wrong.
2. They pick a category — Broken, UX, Visual, Performance, Content, Other — and describe the problem.
3. The client captures context automatically (below) and posts one payload to the backend.
4. The backend, holding the tracker token, creates the issue.
5. **A human reads it and decides.** Nothing is fixed automatically.

## The Human Gate

**A report never triggers a fix.** The reporter creates an issue; a developer reads the queue, picks one, and asks their coding agent to work on that specific issue by number.

This boundary is the security property, not a workflow preference. An anonymous user who can file a report that automatically becomes a code change controls the codebase through a text box. Keep the two halves separate: reporting is public and automated, fixing is authenticated and human-initiated.

## Capture Payload

Capture what makes the report reproducible and nothing else:

- URL including query string, and the route pattern
- A stable selector for the element, plus its visible text
- Viewport size, user agent, and the app version or commit SHA
- The last few console errors and failed network requests
- Timestamp and, when authenticated, the user id — **never** the session token

**Scrub before sending.** The capture runs on a page that may display personal data, and everything captured lands in a tracker issue that is often readable by the whole team, sometimes publicly (`data-protection.md`):

- Redact input values by default — allow-list fields worth capturing, never deny-list.
- Strip `Authorization` headers, cookies, and anything matching a token or key pattern from captured requests (`secrets-management.md`).
- A screenshot is the highest-risk item: it captures whatever is on screen, including another user's data. Mask input fields and anything marked sensitive before upload, or make screenshots opt-in per report.

## The Endpoint

`POST /issues/report` is an unauthenticated write path that creates external records, so it is an abuse target — treat it as untrusted input end to end (`untrusted-input.md`, `access-control.md`):

- **Rate limit per IP and per session**, tighter than a normal read endpoint (`rate-limiting.md`). Without it, one script fills the tracker.
- **Cap every field**: description length, screenshot bytes, number of captured errors. Reject oversized payloads rather than truncating silently.
- **Validate the category against the fixed list** — never pass a user string into an issue label.
- **Treat all text as untrusted** when composing the issue body. Escape it; never interpolate into a command, a template that executes, or a Markdown link target.
- **The tracker token lives server-side only** (`secrets-management.md`). A client that can create issues directly is a client that can create anything.
- Consider requiring authentication when the app is already behind a login — it removes most of the abuse surface at no cost to a user who is signed in.

## Issue Content

- Title: category plus a short slice of the description — greppable, not the whole essay.
- Body: the description, then the captured context in a fixed order so issues are skimmable.
- Label by category, and mark the source as automated so triage can tell reports from hand-written issues.
- Deduplicate on URL plus selector plus category before creating: ten users hitting the same broken button should be one issue with a count, not ten issues.

## Failure Handling

The tracker will be down or rate-limited sometimes. Queue the report and retry, or persist it and surface the failure to an operator — never drop it silently, and never show the user a success message for a report that was not filed (`error-handling.md`).
