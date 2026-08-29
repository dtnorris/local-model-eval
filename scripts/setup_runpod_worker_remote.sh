#!/usr/bin/env bash
set -euo pipefail

# Mac-side wrapper for configuring an already-created RunPod worker.
# Resolves direct SSH coordinates from the repo-local .env and streams
# setup_runpod_ollama_worker.sh into the selected pod.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"
REMOTE_SETUP="$ROOT/scripts/setup_runpod_ollama_worker.sh"
WORKER=""
SSH_USER=root
IDENTITY="$HOME/.ssh/id_ed25519"
REMOTE_ARGS=()

usage() {
  cat <<'USAGE'
Usage:
  setup_runpod_worker_remote.sh --worker N [remote setup arguments]

Worker addressing is loaded from repo-local .env:
  RUNPOD_BURST_N_HOST
  RUNPOD_BURST_N_SSH_PORT

Wrapper options:
  --worker N          Burst worker number (required)
  --user USER         SSH user (default: root)
  --identity PATH     SSH private key (default: ~/.ssh/id_ed25519)
  -h, --help          Show this help

All other arguments are forwarded unchanged to setup_runpod_ollama_worker.sh.

Example:
  scripts/setup_runpod_worker_remote.sh \
    --worker 2 \
    --clean \
    --model qwen3.6:27b \
    --expect-digest qwen3.6:27b=9d5803d493a991af27b9441c098aa56f2ed7bbd260877f075ec09b575c049bc3
USAGE
}

ts() { date '+%H:%M:%S'; }
info() { printf '[%s] %s\n' "$(ts)" "$*"; }
die() { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    --worker)
      [[ $# -ge 2 ]] || die "--worker requires a value"
      WORKER="$2"
      shift 2
      ;;
    --user)
      [[ $# -ge 2 ]] || die "--user requires a value"
      SSH_USER="$2"
      shift 2
      ;;
    --identity)
      [[ $# -ge 2 ]] || die "--identity requires a value"
      IDENTITY="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      REMOTE_ARGS+=("$1")
      shift
      ;;
  esac
done

[[ "$WORKER" =~ ^[1-9][0-9]*$ ]] || { usage >&2; die "--worker must be a positive integer"; }
[[ -f "$ENV_FILE" ]] || die "missing $ENV_FILE; copy .env.example to .env and fill in real RunPod values"
[[ -f "$REMOTE_SETUP" ]] || die "remote setup script not found: $REMOTE_SETUP"
[[ -f "$IDENTITY" ]] || die "SSH identity not found: $IDENTITY"

info "[1/4] Loading worker $WORKER connection settings from $ENV_FILE ..."
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

host_var="RUNPOD_BURST_${WORKER}_HOST"
ssh_port_var="RUNPOD_BURST_${WORKER}_SSH_PORT"
HOST="${!host_var:-}"
SSH_PORT="${!ssh_port_var:-}"

[[ -n "$HOST" ]] || die "$host_var is not set in $ENV_FILE"
[[ -n "$SSH_PORT" ]] || die "$ssh_port_var is not set in $ENV_FILE"
case "$HOST" in
  *'<'*|*'>'*) die "$host_var still contains a placeholder: $HOST" ;;
  ssh.runpod.io|*.ssh.runpod.io)
    die "$host_var points at RunPod proxy SSH; use the Direct TCP host/IP"
    ;;
esac
case "$SSH_PORT" in
  *'<'*|*'>'*) die "$ssh_port_var still contains a placeholder: $SSH_PORT" ;;
esac
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] || die "$ssh_port_var must be an integer"

info "[2/4] Resolved worker $WORKER -> ${SSH_USER}@${HOST}:${SSH_PORT}"
info "[3/4] Checking direct SSH reachability and key authentication ..."
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

remote_command="bash -s --"
for arg in "${REMOTE_ARGS[@]}"; do
  printf -v quoted '%q' "$arg"
  remote_command+=" $quoted"
done

info "[4/4] Streaming setup_runpod_ollama_worker.sh to worker $WORKER ..."
info "Remote setup progress follows; model pulls and rsync may take several minutes."
ssh \
  -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=accept-new \
  -p "$SSH_PORT" \
  -i "$IDENTITY" \
  "$SSH_USER@$HOST" \
  "$remote_command" \
  < "$REMOTE_SETUP"

info "Worker $WORKER remote setup PASS."
