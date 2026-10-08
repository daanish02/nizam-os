Server: nizam-vps, Ubuntu, UTC+0
Repos: ~/nizam-os (infrastructure), ~/nizam-vault (knowledge vault)

Vault root: ~/nizam-vault/commons/
Note format: {domain}--{title-slug}.md

knowledge-service MCP: stdio, managed by systemd user service knowledge-service.service
knowledge-service connects to PostgreSQL as svc_knowledge (knowledge schema only)
Embeddings: google/gemini-embedding-2 (768-dim) via LiteLLM at localhost:4000

Domains (10, controlled — use exact strings):
  Mind & Behavior, Mathematics & Logic, Physical Sciences, Life Sciences,
  Earth & Space, Technology & Engineering, Intelligence & Computation,
  Economics & Finance, Society & Culture, Creative Arts

Profile config: ~/nizam-os/config/hermes-curator-config.yaml
Profile secrets: ~/nizam-os/secrets/hermes-curator.env (symlinked from ~/.hermes/profiles/curator/.env)

Discord bot: Noor, curator profile, server: Darbar Test
Channel:
- learning: 1517682482328371242
