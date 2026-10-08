#!/usr/bin/env bash
# Writes scripts/start.sh and scripts/stop.sh at the project root.
# Detects which services exist on disk (backend/, services/<role>/, frontend/)
# and generates a single-command start/stop for all of them.
#
# Must run AFTER scaffold scripts (python-backend.sh / go-backend.sh /
# nextjs-frontend.sh) so the directories are already present.
#
# Usage (from project root): bash feanor/scripts/scaffold/write-dev-scripts.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
scripts_dir="$root/scripts"
mkdir -p "$scripts_dir"

# ── Discover services ────────────────────────────────────────────────────────

python_services=()
go_services=()
frontend_dir=""

collect_backend() {
    local dir="$1"
    if [ -f "$root/$dir/pyproject.toml" ]; then
        python_services+=("$dir")
    elif [ -f "$root/$dir/go.mod" ]; then
        go_services+=("$dir")
    fi
}

if [ -d "$root/services" ]; then
    for svc in "$root/services"/*/; do
        [ -d "$svc" ] || continue
        rel="${svc#"$root/"}"
        rel="${rel%/}"
        collect_backend "$rel"
    done
elif [ -d "$root/backend" ]; then
    collect_backend "backend"
fi

if [ -d "$root/frontend" ]; then
    frontend_dir="frontend"
fi

all_services=("${python_services[@]}" "${go_services[@]}")
[ -n "$frontend_dir" ] && all_services+=("$frontend_dir")

if [ "${#all_services[@]}" -eq 0 ]; then
    echo "No services detected — nothing to write." >&2
    exit 1
fi

# ── Port assignment ──────────────────────────────────────────────────────────
# Python services start at 8000, Go at 8100, frontend at 3000.

declare -A service_port
declare -A service_type

py_port=8000
go_port=8100

for svc in "${python_services[@]}"; do
    service_port["$svc"]=$py_port
    service_type["$svc"]="python"
    py_port=$((py_port + 1))
done

for svc in "${go_services[@]}"; do
    service_port["$svc"]=$go_port
    service_type["$svc"]="go"
    go_port=$((go_port + 1))
done

if [ -n "$frontend_dir" ]; then
    service_port["$frontend_dir"]=3000
    service_type["$frontend_dir"]="nextjs"
fi

# ── Collect all ports for kill_port calls ───────────────────────────────────

all_ports=()
for svc in "${all_services[@]}"; do
    all_ports+=("${service_port[$svc]}")
done

ports_str=$(printf " %s" "${all_ports[@]}")
ports_str="${ports_str:1}"   # trim leading space

# ── Shared process helpers emitted into both start.sh and stop.sh ────────────
# Port lookup and process termination differ per platform. Probe for the tool
# that exists rather than assuming one: lsof (macOS, most Linux), ss
# (Linux without lsof), netstat+taskkill (Windows / Git Bash). A port that
# cannot be freed is a hard failure — starting anyway would silently bind-fail
# or attach to a stale process.

emit_process_helpers() {
cat <<'HELPERS'
_kill_pid() {
    local pid="$1"
    if [ "${OS:-}" = "Windows_NT" ] && command -v taskkill >/dev/null 2>&1; then
        taskkill //F //PID "$pid" >/dev/null 2>&1
    else
        kill -9 "$pid" >/dev/null 2>&1
    fi
}

_pids_on_port() {
    local port="$1"
    if command -v lsof >/dev/null 2>&1; then
        lsof -t -i TCP:"$port" -s TCP:LISTEN 2>/dev/null || true
    elif command -v ss >/dev/null 2>&1; then
        ss -lptnH "sport = :$port" 2>/dev/null | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u || true
    elif command -v netstat >/dev/null 2>&1; then
        netstat -ano 2>/dev/null | grep -E '(LISTENING|LISTEN)' \
            | grep -E "[:.]${port}[[:space:]]" | awk '{print $NF}' | grep -E '^[0-9]+$' | sort -u || true
    else
        echo "__NO_TOOL__"
    fi
}

kill_port() {
    local port="$1" pids attempt
    for attempt in 1 2 3; do
        pids=$(_pids_on_port "$port")
        if [ "$pids" = "__NO_TOOL__" ]; then
            echo "Cannot free port $port: none of lsof, ss, or netstat is available." >&2
            return 1
        fi
        [ -n "$pids" ] || return 0
        for pid in $pids; do
            _kill_pid "$pid"
        done
        sleep 1
    done
    echo "Port $port is still in use by PID(s): $(_pids_on_port "$port")" >&2
    return 1
}
HELPERS
}

# ── Generate start.sh ────────────────────────────────────────────────────────

start_file="$scripts_dir/start.sh"

{
cat <<'HEADER'
#!/usr/bin/env bash
# Starts all services, killing anything already on their ports first.
# Logs go to .run/<service>.log; PIDs to .run/<service>.pid.
# Stop everything: ./scripts/stop.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run_dir="$root/.run"
mkdir -p "$run_dir"

HEADER

emit_process_helpers

cat <<'HEADER'

wait_http() {
    local url="$1" timeout="$2" waited=0
    while [ "$waited" -lt "$timeout" ]; do
        if curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null | grep -qE "^(200|404)$"; then
            return 0
        fi
        sleep 0.5
        waited=$((waited + 1))
    done
    return 1
}

HEADER

# Load .env files
for svc in "${all_services[@]}"; do
    env_file="\$root/$svc/.env"
    cat <<ENV
if [ -f "\$root/$svc/.env" ]; then set -a; source "\$root/$svc/.env"; set +a; fi
ENV
done

echo ""
echo "echo \"Stopping anything already on $ports_str...\""
for port in "${all_ports[@]}"; do
    echo "kill_port $port"
done
echo "sleep 1"
echo ""

# Start commands per service type
for svc in "${all_services[@]}"; do
    port="${service_port[$svc]}"
    type="${service_type[$svc]}"
    name="${svc//\//_}"   # services/api -> services_api

    case "$type" in
        python)
            cat <<CMD

echo "Starting $svc (uvicorn :$port)..."
(cd "\$root/$svc" && nohup uv run uvicorn app.main:app --port $port > "\$run_dir/$name.log" 2>&1 &
 echo \$! > "\$run_dir/$name.pid")
CMD
            ;;
        go)
            cat <<CMD

echo "Starting $svc (go run :$port)..."
(cd "\$root/$svc" && nohup go run ./cmd/... --port $port > "\$run_dir/$name.log" 2>&1 &
 echo \$! > "\$run_dir/$name.pid")
CMD
            ;;
        nextjs)
            cat <<CMD

echo "Starting $svc (bun dev :$port)..."
(cd "\$root/$svc" && nohup bun run dev > "\$run_dir/$name.log" 2>&1 &
 echo \$! > "\$run_dir/$name.pid")
CMD
            ;;
    esac
done

echo ""

# Wait + report per service
for svc in "${all_services[@]}"; do
    port="${service_port[$svc]}"
    type="${service_type[$svc]}"

    if [ "$type" = "python" ]; then
        probe="http://127.0.0.1:$port/openapi.json"
        timeout=120
    elif [ "$type" = "nextjs" ]; then
        probe="http://127.0.0.1:$port"
        timeout=60
    else
        probe="http://127.0.0.1:$port/healthz"
        timeout=60
    fi

    cat <<WAIT

echo "Waiting for $svc..."
if wait_http "$probe" $timeout; then
    echo "  $svc up: http://localhost:$port"
else
    echo "  $svc did not come up — check \$run_dir/${svc//\//_}.log"
fi
WAIT
done

echo ""
echo "echo \"\""

log_list=$(printf '"%s"' "${all_services[@]/%/.log}" | tr ' ' ',')
echo "echo \"Logs: \$run_dir/{${all_services[*]//\//_}}.log\""
echo "echo \"Stop all: ./scripts/stop.sh\""

} > "$start_file"
chmod +x "$start_file"

# ── Generate stop.sh ─────────────────────────────────────────────────────────

stop_file="$scripts_dir/stop.sh"

{
cat <<'HEADER'
#!/usr/bin/env bash
# Stops services started by start.sh.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run_dir="$root/.run"

HEADER

emit_process_helpers

cat <<'HEADER'

kill_pidfile() {
    local name="$1"
    local pid_file="$run_dir/$name.pid"
    [ -f "$pid_file" ] || return 0
    local pid
    pid=$(cat "$pid_file")
    if [ -n "$pid" ]; then
        if _kill_pid "$pid"; then
            echo "Stopped $name (pid $pid)"
        else
            echo "$name (pid $pid) was not running"
        fi
    fi
    rm -f "$pid_file"
}

HEADER

for svc in "${all_services[@]}"; do
    name="${svc//\//_}"
    echo "kill_pidfile \"$name\""
done

echo ""
echo "# Port sweep catches child processes the pidfile missed"
for port in "${all_ports[@]}"; do
    echo "kill_port $port"
done

echo ""
echo 'echo "Done."'

} > "$stop_file"
chmod +x "$stop_file"

echo "Written:"
echo "  $start_file"
echo "  $stop_file"
echo ""
echo "Services detected:"
for svc in "${all_services[@]}"; do
    echo "  ${service_type[$svc]}  $svc  :${service_port[$svc]}"
done
