#!/usr/bin/env bash
# Scaffolds a Go backend per conventions/go/project-layout.md. Run from
# the project root. Requires a go.mod module path (matches the repo URL,
# per go/project-layout.md's naming rule).
#
# Usage: go-backend.sh [--dir <target-dir>] <module-path> <domain1> [domain2] ...
# Example (single-service, default): go-backend.sh github.com/example/project orders billing
# Example (multi-service backend): go-backend.sh --dir services/worker github.com/example/project/worker jobs
set -e

TARGET_DIR="backend"
if [ "$1" = "--dir" ]; then
  TARGET_DIR="$2"
  shift 2
fi

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 [--dir <target-dir>] <module-path> <domain1> [domain2] ..."
  exit 1
fi

MODULE_PATH="$1"
shift

# Preflight before writing anything: a missing or wrong-version toolchain
# should fail here, not halfway through with a half-scaffolded tree.
FEANOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
uv run "$FEANOR_DIR/scripts/check-toolchain.py" go

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

go mod init "$MODULE_PATH"

mkdir -p cmd/server internal/config
# doc.go, not just mkdir: git doesn't track empty directories, so without a
# real file inside, these silently vanish from the repo the moment anything
# commits — even though the scaffold genuinely created them. Found by
# testing a real commit after a real scaffold run. A bare package doc
# comment is also correct on its own merits — an empty directory isn't a
# valid Go package at all, per code-style-naming.md's doc-comment rule.
cat > internal/config/doc.go <<'EOF'
// Package config holds cross-cutting, environment-dependent tunables.
package config
EOF
for domain in "$@"; do
  mkdir -p "internal/$domain"
  cat > "internal/$domain/doc.go" <<EOF
// Package $domain implements the $domain domain.
package $domain
EOF
done

cat > cmd/server/main.go <<EOF
package main

import (
	"log/slog"
	"net/http"
	"os"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(\`{"success":true,"data":{"status":"ok"}}\`))
	})

	logger.Info("starting server", "port", 8080)
	if err := http.ListenAndServe(":8080", mux); err != nil {
		logger.Error("server stopped", "error", err)
		os.Exit(1)
	}
}
EOF

echo "Scaffolded $TARGET_DIR/ (module $MODULE_PATH) with domains: $*"
echo "Run 'cd $TARGET_DIR && go mod tidy' after adding real dependencies."
