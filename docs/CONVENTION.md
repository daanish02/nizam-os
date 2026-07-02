# Documentation convention

Applies to: nizam-dotfiles, nizam-os. Shared style, consistent across both.

---

## Primary audience

**The primary reader of all docs is Claude Code and Hermes agents, not humans.** The user reads docs to review and annotate, but the majority of consumption is by AI sessions. Write accordingly: be precise, complete, and unambiguous. Assume zero prior context in every document.

---

## Hard rules (non-negotiable)

- **No emojis.** In docs, code, comments, agent responses, or anywhere else.
- **Never modify `~/.hermes/` or Hermes source code.** Configuration only via `hermes/profiles/<name>/`. See `docs/ARCHITECTURE.md` for the full constraint.
- **Single source of truth.** No value defined in two places. When referencing a value from another file, link to it — do not copy it.
- **Primary audience is Claude Code and Hermes agents.** Write all docs precisely and completely. Assume no prior context. Avoid ambiguous references, orphaned pronouns, and approximate values.
- **Never commit.** User commits all changes manually. Never run `git commit`.
- **No "update docs later."** Docs change with code in the same commit. Later never comes.
- **No placeholders in plans.** Every step in `docs/plans/` must contain the actual code, command, and expected output. "TBD", "TODO", and "similar to above" are plan failures.

---

## Principles

- Say what something is before saying how it works.
- Short over long. If a sentence can be cut without losing meaning, cut it.
- Mention the non-obvious. Skip the obvious.
- Docs should be referenceable — write with the assumption that another doc will link here.
- Don't duplicate. One doc owns a topic; others link to it. Duplicated content drifts out of sync.

---

## Voice and tone

- Imperative mood for instructions: "Run this", not "You should run this".
- Active voice: "The script writes a file", not "A file is written by the script".
- Sentence case for all headers: "How it works", not "How It Works".
- Plain English. No buzzwords: no "robust", "leverage", "scalable", "cutting-edge", "seamless".
- Short synonyms: "use" not "utilize", "fix" not "implement a solution for", "run" not "execute".
- No filler openings: never start a doc with "This document describes..." or "In this section we will...".

---

## Writing for AI readers

The primary reader is a Claude Code session or a Hermes agent consuming this as context. AI readers do not skim, but they lose precision when references are ambiguous or information is incomplete.

- Define a term on first use, then use it consistently. Do not alternate between "LiteLLM proxy", "the proxy", and "LiteLLM" — pick one and keep it.
- Never use "the above" or "as mentioned earlier" — restate the noun. AI has no scroll position.
- Avoid orphaned pronouns. "It writes the file" → "The script writes the file."
- One concept per sentence. Compound sentences that chain three conditions degrade comprehension.
- Prefer concrete over abstract. "Runs every 5 minutes via `metrics-services.timer`" beats "runs periodically".
- Put context before detail. State what a section is about in the first sentence, then go into specifics.
- Include exact file paths, port numbers, env var names, and command strings. Approximate values are errors.
- State current status explicitly. "Non-functional until X" is better than implying something works when it does not.

---

## README

Non-technical opener (what it is, why it exists). Then: what it covers, repo layout, boundary, setup, comparison table. Comparison table goes near the bottom. No emojis.

---

## docs/

- One file per topic. If a file exceeds ~80 lines, consider splitting.
- Filename: kebab-case (`startup-guide.md`, not `StartupGuide.md`).
- Start with substance. No intro paragraph explaining what the file is about.
- Cross-reference freely using relative links: `[dashboard guide](dashboard.md)` or `[section](file.md#section)`.
- Tables over prose for structured comparisons or option lists.
- All commands in fenced code blocks with language tag.
- Walls of text are a failure. If a section is getting long, it needs a table, a list, or a split.
- Max header depth is `###`. If a section needs `####`, the file needs splitting.
- **Horizontal rules:** use `---` only between H2 sections. Never inside a subsection. No `---` at the very top or bottom of a file.

---

## Repo structure trees

Show directory trees in a `bash` fenced block. Entries describe what a directory **contains**, not what files exist inside it.
```bash
nizam-dotfiles/
├── shell/      zsh config, prompt theme, aliases
├── scripts/    metric collectors, shared logger, install script
├── systemd/    service and timer units for metric collectors
├── config/     logrotate config
├── grafana/    dashboard JSON
├── docs/       setup and reference docs
└── logs/       runtime script output (gitignored)
```

---

## Lists

Use `-` for unordered lists. Use `1.` for ordered steps — write every item as `1.`, let Markdown render the numbering. Never mix within the same list.

---

## Code and scripts

**Script header:** Immediately after the shebang. Describe what the script does and any non-obvious constraint — timer cadence, side effects, dependencies. Four lines is a ceiling, not a target.
```bash
#!/usr/bin/env bash
# Collect top CPU and memory consuming processes for Grafana.
# Excludes transient collection tools (ps, awk, du) that spike briefly at 100%.
# Runs every 30 seconds via metrics-processes.timer.
```
**Python docstrings (Google style):** One-line summary. Expand only when behavior is non-obvious. Omit Args/Returns/Raises when they add nothing beyond the signature.
**Inline comments:** One line max. Only for non-obvious WHY — a hidden constraint, a workaround, a surprising invariant. Never narrate what the code does.

```bash
# du not excluded by default — add it or metrics-disk concurrent run spikes to 100%
EXCLUDE='/\/(ps|awk|grep|sh|bash|du)$/'
```

---

## Diagrams

Prefer Mermaid for diagrams. ASCII art in fenced code blocks is acceptable for simple linear flows. Keep diagrams small — one concept per diagram. If it needs a legend, it is too complex.

---

## Callouts

Use `>` blockquotes for warnings or critical notes that carry real risk or consequence. Use sparingly — overuse makes everything look important. Never for general information or tips.

---

## Tables

Use tables for structured comparisons, option lists, and service inventories. Keep cells short — one idea per cell. No prose in table cells.
| Column | Column |
|--------|--------|
| short  | short  |

---

## Cross-referencing

Write docs so they can be linked. Use relative paths: `[dashboard guide](dashboard.md)` or `[section](file.md#section)`. When referencing another repo, name it — do not link.

---

## Planned vs implemented

Never mix live and planned content without a clear marker. In tables, add a `Status` column:

| Service | Status |
|---|---|
| `finance-service` | Step 4 — planned |
| `metrics-llm` | Live |

For entire sections or files that describe planned work, add a `> Not yet implemented.` blockquote at the top. Never drop planned markers just because the section reads confidently.

---

## What not to write

- "This document describes..."
- "In this section we will cover..."
- "As mentioned above..."
- "Please note that..."
- "It is worth noting that..."
- "Simply run..." (nothing is simple)
- Trailing "Next steps" sections unless they contain specific, actionable links
