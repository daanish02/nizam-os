#!/usr/bin/env bash
# Scaffolds a Next.js frontend per conventions/nextjs/project-layout.md.
# Run from the project root.
#
# Usage: nextjs-frontend.sh <domain1> [domain2] ...
# Example: nextjs-frontend.sh orders billing
set -e

FEANOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Preflight before writing anything: a missing or wrong-version toolchain
# should fail here, not halfway through with a half-scaffolded tree.
uv run "$FEANOR_DIR/scripts/check-toolchain.py" bun

# Versions come from conventions/versions.toml — the single declaration read by
# this script and by audit-mechanical.py. NOT @latest: a live run installed
# Next 16.3.4 against a documented pin of ~15.3.0, which is days of code
# written against the wrong App Router API before anyone notices.
#
# check-toolchain.py --pin does the reading, so this script never parses TOML
# and never has to convert paths: under Git Bash $FEANOR_DIR is a POSIX path
# (/c/...) that the Windows Python binary cannot open, but `uv run <script>`
# resolves the script itself and the script finds its own sibling files.
CNA_PIN="$(uv run "$FEANOR_DIR/scripts/check-toolchain.py" --pin create-next-app)"
NEXT_VERIFY="$(uv run "$FEANOR_DIR/scripts/check-toolchain.py" --verify-range next)"
SHADCN_PIN="$(uv run "$FEANOR_DIR/scripts/check-toolchain.py" --pin shadcn)"

bunx "create-next-app@$CNA_PIN" frontend \
  --typescript --tailwind --app --src-dir \
  --import-alias "@/*" --eslint --use-bun --yes

# create-next-app inits its own nested git repo — found by testing for real.
# frontend/ must be a plain directory in the project's single top-level repo,
# not a separate one (a nested .git behaves like a broken submodule the
# moment the parent repo tries to track it).
rm -rf frontend/.git

# create-next-app also scaffolds AGENTS.md and CLAUDE.md — NOT touched here,
# on purpose. AGENTS.md is Next.js's own auto-generated warning that this
# version has breaking API changes vs. an LLM's training data (regenerated
# by `next dev` if deleted, so removing it is pointless); frontend/CLAUDE.md
# is just a one-line `@AGENTS.md` import, distinct from and not conflicting
# with the project-root CLAUDE.md.

cd frontend

mkdir -p src/features src/components/ui src/lib
# .gitkeep on every dir that's genuinely empty right after scaffold — git
# does not track empty directories, so without this they silently vanish
# the moment anything commits, even though the scaffold script did create
# them. Found by testing a real commit after a real scaffold run.
touch src/components/ui/.gitkeep src/lib/.gitkeep
for domain in "$@"; do
  mkdir -p "src/features/$domain/components"
  touch "src/features/$domain/actions.ts" "src/features/$domain/schema.ts"
  touch "src/features/$domain/components/.gitkeep"
done

bun add zod react-hook-form @hookform/resolvers
# -b radix AND -p nova are both required, not optional: `-y` alone does NOT
# skip either the component-library prompt or the preset prompt (a real bug
# found by dry-running `-y` alone, then `-y -b radix` alone — each hung
# waiting for interactive input in turn). -b radix matches styling-ui.md's
# Radix-based shadcn/ui choice; -p nova is shadcn's own documented default
# preset, kept explicit here rather than implied.
#
# These flags are specific to shadcn 4.x. Pinning the CLI is what keeps them
# valid: 2.x had no `-p` at all and could not parse Tailwind v4 CSS, so an
# unpinned CLI drifting across a major would break the scaffold silently.
# Re-verify them when changing frameworks.shadcn in conventions/versions.toml.
bunx "shadcn@$SHADCN_PIN" init -y -b radix -p nova

# Assert what actually landed. create-next-app@<pin> is expected to install a
# matching `next`, but a registry surprise or a transitive bump would otherwise
# ship the wrong major silently — the exact failure this script already had.
INSTALLED_NEXT="$(grep -o '"next": *"[^"]*"' package.json | head -1 | sed 's/.*"next": *"//; s/"//; s/^[\^~]//')"
if ! uv run "$FEANOR_DIR/scripts/check-toolchain.py" --satisfies "$INSTALLED_NEXT" "$NEXT_VERIFY"; then
  echo ""
  echo "BLOCKED: installed next $INSTALLED_NEXT is outside $NEXT_VERIFY."
  echo "conventions/versions.toml pins create-next-app to $CNA_PIN, which should"
  echo "have produced a matching next. Something upstream changed — reconcile the"
  echo "pin before building against this version."
  exit 1
fi

echo "Scaffolded frontend/ with domains: $* (next $INSTALLED_NEXT)"
