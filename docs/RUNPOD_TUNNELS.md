# Managed RunPod Tunnels

`bin/lme runpod-tunnels` owns the local SSH forwarding processes that expose the current RunPod fleet's Ollama servers to LME.

It replaces hand-started tunnel terminals and the older one-worker shell helper for normal fleet operation.

## Start

```bash
bin/lme runpod-tunnels --workers 1-5
```

Equivalent explicit form:

```bash
bin/lme runpod-tunnels start --workers 1-5
```

The command reads only the authoritative current fleet. Each worker's local endpoint comes from `fleet.json`, for example `http://127.0.0.1:11441` for `burst_1`.

All selected tunnels are spawned directly as SSH process groups before readiness polling begins. No shell background loop or naked `wait` is used.

For every worker LME records:

- fleet ID and pod ID;
- SSH host and port;
- local and remote forwarding ports;
- SSH PID;
- an exact process-identity signature used before later termination;
- process and health status;
- Ollama version returned by `/api/version`;
- start/stop/health-check timestamps;
- worker-specific SSH log; and
- worker-specific `known_hosts` file.

State is atomically written beneath the current fleet:

```text
output/runpod-fleets/<fleet-id>/tunnels/
  tunnels.json
  burst_1.log
  known_hosts-burst_1
  ...
```

The per-worker `known_hosts` files avoid concurrent SSH processes racing to rewrite the same global `~/.ssh/known_hosts` file.

## Health

Tunnel startup does not declare PASS merely because an SSH PID exists. LME polls the forwarded local endpoint and requires a successful Ollama `/api/version` response.

A typical success is:

```text
PASS: burst_1 tunnel healthy | pid=12345 | http://127.0.0.1:11441 | Ollama 0.33.2
```

If some workers become healthy and another fails, the healthy tunnels are preserved, the failed/unhealthy state is recorded, and the command exits non-zero. This mirrors bootstrap behavior: partial success is visible rather than hidden.

While startup is waiting, a fleet tunnel heartbeat is emitted every five seconds.

## Status

```bash
bin/lme runpod-tunnels status
```

Status defaults to every active worker in the current fleet and checks both:

1. whether the recorded SSH process is still alive and still matches the exact recorded forwarding identity; and
2. whether Ollama is reachable through the local forwarded endpoint.

An unhealthy, missing, stale, or PID-mismatched tunnel makes the status command exit non-zero.

## Stop

```bash
bin/lme runpod-tunnels stop --workers 1-5
```

or:

```bash
bin/lme runpod-tunnels stop --all
```

Before sending a signal, LME verifies that the live PID still matches the recorded forwarding specification, SSH port, and target host. A PID that has been reused by an unrelated process is not killed.

Managed tunnels receive TERM as a process group, followed by KILL only if they remain alive after a short grace period.

`Ctrl-C` during a start stops only the tunnels created by that invocation and records the resulting state.

## Local-port safety

A new tunnel refuses to start if its expected localhost port is already occupied by an unmanaged process. LME does not silently replace or route around an unexplained listener.

## Legacy helper

`scripts/runpod_ollama_tunnel.sh` remains available as a low-level/manual fallback. In worker mode its artifacts are redirected beneath the current fleet's `tunnels/legacy/` directory; explicit host/port mode uses `output/manual-tunnels/`. The managed `bin/lme runpod-tunnels` command is the authoritative fleet workflow.
