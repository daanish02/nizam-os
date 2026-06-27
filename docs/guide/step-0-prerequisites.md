# Step 0 — Prerequisites

Everything that must be on the server before Step 1.  
Machine-level setup (shell, git, security monitoring) is in `~/.nizam-dotfiles/docs/startup.md` — do that first.

---

## Language runtimes

```bash
# uv — Python package and project manager
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.local/bin/env   # or open a new shell

# Node + npm
sudo apt install -y nodejs npm
```

---

## System tools

```bash
# age + sops — encrypts nizam.env so credentials can be committed safely
sudo apt install -y age
SOPS_VERSION=$(curl -s https://api.github.com/repos/getsops/sops/releases/latest | jq -r .tag_name)
sudo curl -Lo /usr/local/bin/sops \
  "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.amd64"
sudo chmod +x /usr/local/bin/sops

# dbmate — SQL migrations
sudo curl -fsSL -o /usr/local/bin/dbmate \
  https://github.com/amacneil/dbmate/releases/latest/download/dbmate-linux-amd64
sudo chmod +x /usr/local/bin/dbmate

# firejail — sandbox for dev/CTO sub-agents
sudo apt install -y firejail

# yt-dlp
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
  -o /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp
```

---

## Infrastructure

```bash
# PostgreSQL 16 + pgvector
sudo apt install -y postgresql postgresql-contrib postgresql-16-pgvector

# pg_search (ParadeDB BM25) — check releases page for latest version
curl -L "https://github.com/paradedb/paradedb/releases/download/v0.24.0/postgresql-16-pg-search_0.24.0-1PARADEDB-noble_amd64.deb" \
  -o /tmp/pg_search.deb
sudo apt install -y /tmp/pg_search.deb

# Enable pg_search — add to shared_preload_libraries in postgresql.conf
sudo nano /etc/postgresql/16/main/postgresql.conf

# Redis
sudo apt install -y redis-server

# Prometheus
sudo apt install -y prometheus

# Grafana
sudo mkdir -p /etc/apt/keyrings
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | \
  sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt update && sudo apt install -y grafana

sudo systemctl enable --now postgresql redis-server prometheus grafana-server
sudo systemctl restart postgresql   # pick up pg_search in shared_preload_libraries
```

---

## Secrets

Set up nizam.env before Step 1 — LiteLLM needs its credentials to start.

```bash
# Generate age key — back this up (Bitwarden + encrypted USB)
age-keygen -o ~/.nizam-dotfiles/secrets/nizam-age-key.txt
chmod 600 ~/.nizam-dotfiles/secrets/nizam-age-key.txt

# Tell sops where the key lives (add to ~/.zshrc)
echo 'export SOPS_AGE_KEY_FILE=~/.nizam-dotfiles/secrets/nizam-age-key.txt' >> ~/.zshrc
source ~/.zshrc
```

Fill in credentials:

```bash
cp ~/.nizam-dotfiles/secrets/nizam.env.example ~/.nizam-dotfiles/secrets/nizam.env
nano ~/.nizam-dotfiles/secrets/nizam.env
```

| Key | Where to get |
|---|---|
| `OPENROUTER_API_KEY` | openrouter.ai → Keys |
| `LITELLM_MASTER_KEY` | `openssl rand -hex 16`, prefix `sk-nizam-` |
| `LITELLM_DB_PASSWORD` | `python3 -c "import secrets; print(secrets.token_urlsafe(24))"` |
| `DISCORD_BOT_TOKEN` | discord.com/developers → New App → Bot → Token (Step 2) |

```bash
# Encrypt and commit the encrypted copy
~/.nizam-dotfiles/scripts/encrypt-env.sh
```

---

## Database

```bash
source ~/.nizam-dotfiles/secrets/nizam.env
bash ~/.nizam-os/scripts/setup/setup-db.sh
```

---

## Verify

```bash
uv --version && node --version && dbmate --version
sops --version && age --version
sudo systemctl is-active postgresql redis-server prometheus grafana-server
```

---

## Troubleshooting

```bash
# PostgreSQL not starting
sudo journalctl -u postgresql -n 30 --no-pager
sudo systemctl status postgresql --no-pager

# DB setup-db.sh fails (role already exists, etc.)
sudo -u postgres psql -c "\du"   # list existing roles
sudo -u postgres psql -c "\l"    # list databases

# pg_search not loading (shared_preload_libraries)
sudo grep shared_preload_libraries /etc/postgresql/16/main/postgresql.conf
sudo journalctl -u postgresql -n 10 --no-pager | grep -i "error\|pg_search"

# sops can't find key
echo $SOPS_AGE_KEY_FILE             # must point to ~/.nizam-os/secrets/nizam-age-key.txt
ls -la "$SOPS_AGE_KEY_FILE"         # must exist and be chmod 600

# sops decrypt fails ("no age identity found")
age-keygen -y ~/.nizam-os/secrets/nizam-age-key.txt   # prints public key
head -3 ~/.nizam-os/secrets/nizam.env.enc              # first line shows recipient key — must match above
```
