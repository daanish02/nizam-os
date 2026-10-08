---
type: convention
title: Accessibility (WCAG)
description: WCAG 2.1 AA baseline for Next.js/React frontends — semantic structure, keyboard/focus, forms, ARIA, motion, and the Biome a11y lint gate. Load for any ticket touching a page, component, or form.
applies_to: [nextjs]
tags: [nextjs, accessibility, a11y, wcag]
---

# Accessibility (WCAG)

## Target

WCAG 2.1 AA. Not optional-tier — every project shipped to real users meets this baseline, same standing as `security.md`.

## Semantic Structure

- Landmark elements (`main`, `nav`, `header`, `footer`) — one `main` per page.
- Heading hierarchy has no skipped levels (`h1` → `h2` → `h3`, never `h1` → `h3`). Exactly one `h1` per page.
- `button` for actions, `a` for navigation. `div`/`span` + `onClick` is not a button — it has no keyboard semantics, no focus ring, no accessible role.

## Keyboard & Focus

- Every interactive element reachable and operable via keyboard alone (`Tab`, `Enter`/`Space`, `Esc` where applicable).
- Visible focus indicator on every focusable element. Never `outline: none` without a replacement focus style — removing focus rings for aesthetics is a top WCAG failure.
- Tab order follows visual/reading order. Don't fight it with `tabIndex` values above `0`.
- Modals/dialogs (`shadcn`/Radix `Dialog`, `AlertDialog`, `Popover`, etc.) trap focus while open and return it to the triggering element on close — Radix primitives handle this correctly out of the box; don't rebuild focus trapping by hand.

## Forms

- Every input has a programmatically associated label (`<label htmlFor>` or `aria-label`/`aria-labelledby`). A placeholder is not a label — it disappears on input and isn't announced by all screen readers.
- Validation errors are tied to their field via `aria-describedby` and announced (e.g. `role="alert"` or `aria-live="polite"` on the error container), not just rendered as nearby red text.
- Required/invalid state conveyed through `aria-required`/`aria-invalid`, not color alone.

## Images & Media

- Meaningful `alt` text on every informative image. `alt=""` only for genuinely decorative images (the image adds nothing a screen-reader user needs).
- Video/audio content shipped to users ships with captions or a transcript.

## Color & Contrast

- WCAG AA contrast minimum (4.5:1 normal text, 3:1 large text/UI components) in **both** light and dark themes — see `styling-ui.md` for theme mechanics.
- Never convey state (error, success, required, disabled) through color alone — pair with an icon, text, or pattern.

## ARIA

- No ARIA is better than bad ARIA: prefer semantic HTML first. Only reach for `role`/`aria-*` attributes when no native element expresses the semantics, or when a Radix primitive doesn't already supply them.
- Never override a native element's implicit role without a real reason — `<div role="button">` is a worse button than `<button>`.

## Motion

- Respect `prefers-reduced-motion`: non-essential animation (parallax, auto-playing transitions) is disabled or reduced for users who request it.

## Linting Enforcement (Mechanical Gate)

- Biome's `recommended` ruleset (mandated in `../typescript/tooling.md`) enables its `a11y` rule group by default — this is the project's actual, automatic gate against missing `alt`, invalid ARIA roles/attributes, non-interactive elements with click handlers, and similar violations.
- `linter.rules.recommended: true` in `biome.json` must not be overridden to disable the `a11y` group. `bunx biome check` failing on an `a11y` rule blocks the same way a `tsc` type error does — see the enforcement ladder in `../../meta/determinism-standard.md`.

## Manual Verification (What Lint Can't Catch)

Lint catches structural mistakes, not experience. Before shipping a new interactive component or flow:

- Keyboard-only pass: unplug the mouse, complete the flow with `Tab`/`Enter`/`Esc` only.
- Screen-reader spot-check (VoiceOver on macOS, NVDA on Windows) on any new interactive pattern (modal, custom dropdown, form with dynamic errors).

This is judgment, not a script — see `../../meta/determinism-standard.md`'s distinction between mechanical and judgment steps.

## Related

- `styling-ui.md` — color token definition and light/dark contrast mechanics.
- `../typescript/tooling.md` — Biome baseline that carries the `a11y` lint rules.
