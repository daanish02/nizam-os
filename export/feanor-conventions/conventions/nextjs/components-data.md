---
type: convention
title: Components & Data
description: Next.js rules for Server vs. Client Component boundaries, data fetching with Server Actions, form validation, and minimising client state.
applies_to: [nextjs]
tags: [nextjs, components, data-fetching, forms, state]
---

# Components & Data

## Data Fetching

- Fetch data in Server Components / Server Actions, not client-side `useEffect` + `fetch` — the framework's built-in request deduplication and caching only work server-side.
- Server Actions (`"use server"`) for mutations, colocated in each domain's `features/<domain>/actions.ts` — not scattered ad-hoc API routes for things a Server Action can do directly.
- Only create a real `app/api/` route when something genuinely needs an HTTP endpoint (a webhook receiver, a third-party integration callback) — not as a default way to move data.

## Forms & Validation

- `Zod` schemas define the shape once, colocated per domain (`features/<domain>/schema.ts`), reused for both client-side form validation and server-side input validation at the Server Action boundary — never trust client validation alone.
- `React Hook Form` + a Zod resolver for form state — not hand-rolled `useState` per field.

## State Minimalism

- Default to no client state. Reach for `useState`/`useReducer` only for state that's genuinely ephemeral and local to one interactive component.
- URL search params for state that should be shareable/bookmarkable (filters, pagination, tabs) — not client state that resets on refresh.
- A global state library (Zustand, Jotai, etc.) is added only when a project has real evidence of needing state shared across distant parts of the tree that Server Components/URL state can't cover — document why when it's added, don't start with one.

## Loading & Error States

- `loading.tsx` for route-level loading UI (Suspense boundary), not a manual `isLoading` flag for a page-level fetch.
- Skeletons/spinners live with the component they cover, not a single generic app-wide spinner.
