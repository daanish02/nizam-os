---
type: engine
title: Feanor Agents Index
description: Index of all phase agent system prompts; read this to find which agent drives a given slash command or pipeline stage.
applies_to: [all]
tags: [agents, index]
---

# Feanor Agents Catalog

Agents represent the primary system prompts driving Feanor's state machine transitions. Each prompt enforces explicit constraints, disk-backed artifact inputs/outputs, and strict verification gates.

---

## Phase Agents

- [Requirements Agent](./requirements-agent.md) - Interrogates stakeholders, classifies CP/CN/FR, validates traceability, produces `docs/SRS.md` (`/reqs`, `/brainstorm`).
- [Product Agent](./product-agent.md) - Reads locked SRS and distills into business-readable `docs/PRD.md` (`/prd`).
- [Architect Agent](./architect-agent.md) - Designs high-level system topology, file scaffolding, interface contracts, and emits ADRs (`/hld`, `/scaffold`, `/specs`).
- [Planner Agent](./planner-agent.md) - Decomposes specs into atomic 2-to-5-minute execution tickets; gates on PROPOSED ADRs (`/plan`).
- [Execution Agent](./execution-agent.md) - Executes single tickets with JIT micro-standards and test verification (`/exec`).
- [Validation Agent](./validation-agent.md) - Performs evidence-based architectural and quality audits (`/audit`).
