---
type: template
title: README Template
description: Structural blueprint for the project root README.md — defines sections the architect engine fills during /scaffold to give every project a consistent entry-point document.
applies_to: [readme, documentation]
tags: [template, readme, scaffold]
---

# README Template

Generated into `README.md` at the repo root during `/scaffold`. Fill every `{{PLACEHOLDER}}` from `docs/PRD.md` and `docs/ARCHITECTURE.md`. Do not reference docs/, specs/, tests/, or any internal directory inline — README is for humans who want to understand and run the project, not a table of contents for the repo tree.

---

## Output: `README.md`

```markdown
# {{PROJECT_NAME}}

{{ONE_SENTENCE_TAGLINE}}

## What it does

{{TWO_TO_FOUR_SENTENCE_DESCRIPTION}}
Focus on the problem it solves and what makes it non-trivial. No marketing language.
Pull this from PRD.md § Executive Summary — compress to the essential claim.

## Architecture, briefly

{{THREE_TO_SIX_SENTENCE_ARCHITECTURE_SUMMARY}}
Name the major components and what each one is responsible for. One sentence per boundary.
If the system has a notable design decision (read-only DB access, retry-with-error-feedback,
schema-scale isolation, etc.) call it out here — that's what makes this readable, not just
a list of technologies.

## Stack

- **{{COMPONENT_1}}:** {{LANGUAGE_OR_FRAMEWORK}}, {{PACKAGE_MANAGER}}, {{KEY_LIBRARIES}}
- **{{COMPONENT_2}}:** {{LANGUAGE_OR_FRAMEWORK}}, {{PACKAGE_MANAGER}}, {{KEY_LIBRARIES}}
- **Database:** {{DATABASE_TECH}}

Repeat rows for each top-level component defined in ARCHITECTURE.md. Drop rows that don't exist.

## Repo layout

\`\`\`
{{PROJECT_NAME}}/
├── {{COMPONENT_1_DIR}}/ # {{COMPONENT_1_ONE_LINE_DESCRIPTION}}
├── {{COMPONENT_2_DIR}}/ # {{COMPONENT_2_ONE_LINE_DESCRIPTION}}
├── scripts/ # start/stop and dev-utility scripts
└── docs/ # architecture, schemas, API surface, specs
\`\`\`

One line per top-level directory. No deeper nesting. docs/ always last.

## Quick start

The fastest way to run everything:

\`\`\`bash
{{START_COMMAND}}
\`\`\`

{{START_COMMAND_DESCRIPTION}}
Briefly: what it starts, what ports, what it assumes is already in place (deps installed, .env present).

### Environment

Create `.env` at the repo root:

\`\`\`
{{ENV_VAR_1}}= # {{ENV_VAR_1_DESCRIPTION}}
{{ENV_VAR_2}}= # {{ENV_VAR_2_DESCRIPTION}}
\`\`\`

One var per line. Pull these from ARCHITECTURE.md's external services section and PRD.md's
integration requirements. No secrets — placeholders only.

### {{COMPONENT_1}} setup

\`\`\`bash
cd {{COMPONENT_1_DIR}}
{{INSTALL_COMMAND}}
{{DEV_COMMAND}}
\`\`\`

Repeat a `###` block per component that needs its own setup steps. If a component has no
standalone setup (frontend driven entirely by start script), omit its block.

## Deploying

{{TWO_TO_FOUR_SENTENCE_DEPLOY_SUMMARY}}
Name the recommended host per component, the Dockerfile locations if they exist, and the
one or two env vars that must be set at build/deploy time. No step-by-step instructions —
that belongs in DEPLOYMENT.md.
\`\`\`

---

## Rules for the agent filling this template

- **No cross-references to internal files.** Do not write `see docs/TESTING.md`, `see docs/PRD.md`, `see backend/Dockerfile`, or any path-link to repo files. If something needs explanation, give the two-sentence version inline or leave it out.
- **No duplicate information.** Architecture section covers design; Stack section covers technology; they don't overlap.
- **Placeholders resolve from existing docs, not from guesswork.** If `docs/ARCHITECTURE.md` is not yet written, block and ask — do not invent values.
- **Drop sections that don't apply.** A library with no server has no "Quick start" block. A project with no deploy config omits "Deploying". Use judgment; don't pad.
- **Tagline is one sentence, present tense, no buzzwords.** "Ask questions about your data in plain English; agents find the schema, write the SQL, and visualize the result." not "A powerful AI-native conversational BI tool."
- **Stack bullets are factual, not aspirational.** Only list things actually in `ARCHITECTURE.md`. No "planned" or "TBD" entries.
```
