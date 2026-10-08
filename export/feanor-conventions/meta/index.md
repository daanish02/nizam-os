---
type: meta
title: Feanor System Metadata & Routing
description: Index of Feanor's core mechanics — command routing, context resolution, requirements method, and determinism rules; read this to navigate the meta/ directory.
applies_to: [all]
tags: [meta, index]
---

# Feanor Metadata & Routing

This directory houses the core system mechanics that govern Feanor's execution model.

## Core Mechanics

- [Command Router](./command-router.md) - Slash command triggers, phase gate preconditions, and workflow routing.
- [Context Resolver](./context-resolver.md) - Algorithm for searching conventions/ and retrieving JIT micro-standards.
- [Requirements Interrogation Method](./requirements-checklist.md) - Source classification, problem classification (CP/CN/FR), audience gate, funnel sequencing, zigzag validation, and coverage checklist used by `/reqs`.
- [Architecture Decision Records](./adrs.md) - When to write ADRs, lifecycle (PROPOSED → ACCEPTED → SUPERSEDED/DEPRECATED), index maintenance, and the PROPOSED gate blocking `/plan`.
- [Determinism Standard](./determinism-standard.md) - Deterministic steps become tested scripts; judgment steps stay prose. Also the enforcement ladder and the override convention.
- [Threat Modeling Method](./threat-model.md) - STRIDE per trust boundary during `/hld`; turns abuse cases from `/reqs` into a control list that `/plan` ticketises.
