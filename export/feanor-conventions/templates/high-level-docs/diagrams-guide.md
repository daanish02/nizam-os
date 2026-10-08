---
type: template
title: Excalidraw Diagrams Guide
description: Specifies the three docs/diagrams/*.excalidraw files generated during /hld and the content and richness rules that keep each diagram signal-dense rather than decorative.
applies_to: [hld, diagrams]
tags: [template, diagrams, excalidraw]
---

# Excalidraw Diagrams

Three diagrams, saved to `docs/diagrams/`, generated alongside the high-level docs in the same `/hld` phase run:

| File                                | Audience                   | Content                                                                                                                                             |
| :---------------------------------- | :------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------- |
| `architecture-technical.excalidraw` | Engineers                  | Full technical architecture — services, data stores, infra, network boundaries.                                                                     |
| `architecture-business.excalidraw`  | Non-technical stakeholders | Same system, reframed for a business audience — not dumbed down, just described in terms of capabilities and flow instead of infra/protocol detail. |
| `user-data-flow.excalidraw`         | Either                     | How a user's action or a piece of data moves through the system end to end.                                                                         |

## Rules (apply to all three)

1. **Generic names only.** Never use real service names, table names, variable names, or other identifiers pulled from the actual codebase. Use role-based labels instead: "API Service," "Primary Database," "Auth Provider" — not `orders_api`, `pg_main`, `auth0_client`.
2. **Shallow nesting.** Most diagrams should resolve at depth 0 or depth 1 (top-level boxes and their direct connections). Depth 2 (a box containing sub-boxes) should be rare. Never go to depth 3 or beyond — if a diagram needs that much nesting, it's the wrong diagram; split it or zoom out.
3. **Don't chase completeness.** Omit details that don't change the reader's understanding of the shape of the system. A diagram that captures every queue, retry, and config flag has failed at being a diagram.
4. **Business diagram is not a simplified lie.** Reframing for a non-technical audience means changing vocabulary and omitting implementation detail (message brokers, connection pools) — not removing real steps or misrepresenting what happens.

## Visual Style (apply to every element in every diagram)

| Property                         | Value        | Why                                                                 |
| :------------------------------- | :----------- | :------------------------------------------------------------------ |
| `roughness`                      | `0`          | Architect level — clean, no hand-drawn wobble                       |
| `roundness`                      | `null`       | Sharp corners on all shapes — never `{"type": 3}`                   |
| `fontFamily`                     | `2`          | Nunito (normal sans-serif) — not Excalifont (1) which is hand-drawn |
| `textAlign` (contained text)     | `"center"`   | Horizontal centre inside the box                                    |
| `verticalAlign` (contained text) | `"middle"`   | Vertical centre inside the box                                      |
| `endArrowhead`                   | `"triangle"` | Solid triangle tip — never `"arrow"` (the open default)             |
| `startArrowhead`                 | `null`       | Arrows are one-directional unless explicitly bidirectional          |

"Contained text" means a `text` element whose `containerId` references a shape. Free-standing labels (title, subtitle, legend) keep `verticalAlign: "top"` and their own `textAlign`.

## Excalidraw File Format

An `.excalidraw` file is JSON. Minimal valid shape with the correct style applied:

```json
{
  "type": "excalidraw",
  "version": 2,
  "source": "feanor",
  "elements": [
    {
      "id": "box-1",
      "type": "rectangle",
      "x": 100,
      "y": 100,
      "width": 200,
      "height": 80,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#a5d8ff",
      "fillStyle": "solid",
      "strokeWidth": 1.5,
      "roughness": 0,
      "roundness": null,
      "boundElements": [{ "type": "text", "id": "label-1" }],
      "seed": 1,
      "version": 1,
      "versionNonce": 1
    },
    {
      "id": "label-1",
      "type": "text",
      "x": 120,
      "y": 130,
      "width": 160,
      "height": 25,
      "text": "API Service",
      "fontSize": 15,
      "fontFamily": 2,
      "textAlign": "center",
      "verticalAlign": "middle",
      "containerId": "box-1",
      "roughness": 0,
      "roundness": null,
      "seed": 2,
      "version": 1,
      "versionNonce": 2
    },
    {
      "id": "arrow-1",
      "type": "arrow",
      "x": 300,
      "y": 140,
      "width": 80,
      "height": 0,
      "points": [
        [0, 0],
        [80, 0]
      ],
      "strokeColor": "#1e1e1e",
      "strokeWidth": 2,
      "roughness": 0,
      "roundness": null,
      "endArrowhead": "triangle",
      "startArrowhead": null,
      "seed": 3,
      "version": 1,
      "versionNonce": 3
    }
  ],
  "appState": { "viewBackgroundColor": "#ffffff" },
  "files": {}
}
```

- Use `rectangle`/`ellipse`/`diamond` for nodes, `arrow` for connections, `text` for labels.
- Keep coordinates simple and non-overlapping — this doesn't need to be pixel-perfect, it needs to open cleanly and read left-to-right or top-to-bottom.
- Dashed arrows (`"strokeStyle": "dashed"`) for async, external, or off-critical-path connections — same triangle arrowhead, same roughness 0.
