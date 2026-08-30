# RunPod SSH host-key isolation

RunPod burst workers use ephemeral direct-TCP SSH endpoints. Multiple workers may be bootstrapped concurrently, so their SSH clients must never contend while updating the same global `~/.ssh/known_hosts` file.

## Managed rule

Every worker-specific SSH path uses a fleet-scoped, worker-specific known-hosts file. Remote bootstrap uses:

```text
output/runpod-fleets/<fleet-id>/ssh/known_hosts-burst_<N>
```

Managed tunnels already use separate worker-scoped known-hosts files beneath the current fleet's tunnel state.

The remote bootstrap wrapper passes both:

```text
StrictHostKeyChecking=accept-new
UserKnownHostsFile=<worker-specific path>
```

for its SSH reachability probe and the subsequent streamed bootstrap session.

This preserves host-key verification while eliminating concurrent writes to the user's global OpenSSH host database. It also prevents a host key learned for an older RunPod fleet from being silently reused for a later fleet whose `burst_N` label points at a different ephemeral pod.

The wrapper fails before SSH if `LME_RUNPOD_FLEET_DIR` is unavailable. There is intentionally no fallback to `~/.ssh/known_hosts`, `/dev/null`, or `StrictHostKeyChecking=no`.
