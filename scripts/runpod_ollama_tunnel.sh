#!/usr/bin/env bash
set -euo pipefail

# Create or stop a background SSH tunnel from the Mac to a RunPod direct-TCP SSH endpoint.
# RunPod's ssh.runpod.io proxy does not support the channel forwarding needed here.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$ROOT/output/tunnels"
HOST=""
SSH_PORT=""
LOCAL_PORT=""
REMOTE_PORT=11434
SSH_USER=root
IDENTITY="$HOME/.ssh/id_ed25519"
NAME="burst"
STOP=0
WAIT_SECONDS=30

usage() {
  cat <<'USAGE'
Usage:
  runpod_ollama_tunnel.sh --host HOST --ssh-port PORT --local-port PORT [options]
  runpod_ollama_tunnel.sh --stop --local-port PORT

Options:
  --host HOST          RunPod direct-TCP public IP/host (not ssh.runpod.io)
  --ssh-port PORT      External TCP port mapped to container port 22
  --local-port PORT    Local Mac port for the tunneled Ollama endpoint
  --remote-port PORT   Remote Ollama port (default: 11434)
  --user USER          SSH user (default: root)
  --identity PATH      SSH private key (default: ~/.ssh/id_ed25519)
  --name NAME          Worker label used in the printed env var (default: burst)
  --wait-seconds N     Endpoint readiness timeout (default: 30)
  --stop               Stop the tunnel associated with --local-port
  -h, --help           Show this help

Example:
  scripts/runpod_ollama_tunnel.sh \
    --name burst_2 \
    --host 69.30.85.231 \
    --ssh-port 22127 \
    --local-port 11442
USAGE
}

ts() { date '+%H:%M:%S'; }
info() { printf '[%s] %s\n' "$(ts)" "$*"; }
die() { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --ssh-port) SSH_PORT="${2:-}"; shift 2 ;;
    --local-port) LOCAL_PORT="${2:-}"; shift 2 ;;
    --remote-port) REMOTE_PORT="${2:-}"; shift 2 ;;
    --user) SSH_USER="${2:-}"; shift 2 ;;
    --identity) IDENTITY="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --wait-seconds) WAIT_SECONDS="${2:-}"; shift 2 ;;
    --stop) STOP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$LOCAL_PORT" ]] || { usage >&2; die "--local-port is required"; }
[[ "$LOCAL_PORT" =~ ^[0-9]+$ ]] || die "--local-port must be an integer"
mkdir -p "$STATE_DIR"
PID_FILE="$STATE_DIR/runpod-ollama-${LOCAL_PORT}.pid"
LOG_FILE="$STATE_DIR/runpod-ollama-${LOCAL_PORT}.log"

if [[ $STOP -eq 1 ]]; then
  info "[1/2] Looking for tunnel on local port $LOCAL_PORT ..."
  if [[ ! -f "$PID_FILE" ]]; then
    info "No pid file found; nothing to stop."
    exit 0
  fi
  pid="$(cat "$PID_FILE")"
  info "[2/2] Stopping tunnel pid=$pid ..."
  kill "$pid" 2>/dev/null || true
  rm -f "$PID_FILE"
  info "Tunnel stopped."
  exit 0
fi

[[ -n "$HOST" ]] || { usage >&2; die "--host is required"; }
[[ -n "$SSH_PORT" ]] || { usage >&2; die "--ssh-port is required"; }
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] || die "--ssh-port must be an integer"
[[ "$REMOTE_PORT" =~ ^[0-9]+$ ]] || die "--remote-port must be an integer"
[[ "$WAIT_SECONDS" =~ ^[0-9]+$ ]] || die "--wait-seconds must be an integer"
[[ -f "$IDENTITY" ]] || die "SSH identity not found: $IDENTITY"

case "$HOST" in
  ssh.runpod.io|*.ssh.runpod.io)
    die "RunPod proxy SSH does not support the forwarding channel we need. Use the Direct TCP host/IP and external port mapped to container port 22."
    ;;
esac

if [[ -f "$PID_FILE" ]]; then
  old_pid="$(cat "$PID_FILE")"
  if kill -0 "$old_pid" 2>/dev/null; then
    die "tunnel already appears to be running on local port $LOCAL_PORT (pid=$old_pid)"
  fi
  rm -f "$PID_FILE"
fi

info "[1/4] Checking SSH reachability and key authentication ..."
ssh \
  -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=accept-new \
  -o ConnectTimeout=10 \
  -p "$SSH_PORT" \
  -i "$IDENTITY" \
  "$SSH_USER@$HOST" \
  'printf "direct-ssh-ok\\n"' | grep -q direct-ssh-ok || die "direct SSH authentication failed"
info "Direct SSH PASS."

info "[2/4] Starting background tunnel 127.0.0.1:${LOCAL_PORT} -> pod 127.0.0.1:${REMOTE_PORT} ..."
nohup ssh \
  -N \
  -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=accept-new \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -L "127.0.0.1:${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT}" \
  -p "$SSH_PORT" \
  -i "$IDENTITY" \
  "$SSH_USER@$HOST" \
  >"$LOG_FILE" 2>&1 &
pid=$!
echo "$pid" > "$PID_FILE"
sleep 1
kill -0 "$pid" 2>/dev/null || {
  cat "$LOG_FILE" >&2 || true
  rm -f "$PID_FILE"
  die "SSH tunnel exited immediately"
}
info "Tunnel process running as pid=$pid."

ENDPOINT="http://127.0.0.1:${LOCAL_PORT}"
info "[3/4] Waiting for remote Ollama at $ENDPOINT ..."
ready=0
for ((i=1; i<=WAIT_SECONDS; i++)); do
  if curl -fsS "$ENDPOINT/api/version" > "$STATE_DIR/runpod-ollama-${LOCAL_PORT}-version.json" 2>/dev/null; then
    ready=1
    break
  fi
  if ((i % 5 == 0)); then
    info "Still waiting (${i}/${WAIT_SECONDS}s) ..."
  fi
  sleep 1
done

if [[ $ready -ne 1 ]]; then
  kill "$pid" 2>/dev/null || true
  rm -f "$PID_FILE"
  cat "$LOG_FILE" >&2 || true
  die "tunnel exists but Ollama did not become reachable within ${WAIT_SECONDS}s"
fi

version="$(cat "$STATE_DIR/runpod-ollama-${LOCAL_PORT}-version.json")"
info "Remote Ollama reachable: $version"

safe_name="$(printf '%s' "$NAME" | tr '[:lower:]-' '[:upper:]_' | tr -cd 'A-Z0-9_')"
env_name="LME_${safe_name}_URL"
info "[4/4] Tunnel PASS."
printf '\nUse this endpoint for LME/scorer routing:\n'
printf '  export %s=%s\n' "$env_name" "$ENDPOINT"
printf '  export AF_OLLAMA_BASE_URL=%s\n' "$ENDPOINT"
printf '\nTunnel pid file: %s\n' "$PID_FILE"
printf 'Stop it with:\n  %s --stop --local-port %s\n' "$0" "$LOCAL_PORT"
