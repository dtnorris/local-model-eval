# RunPod Fleet-Scoped State

Every successfully provisioned RunPod fleet has one durable local identity. The state is machine-local and lives under the ignored `output/` tree:

```text
output/runpod-fleets/
  current
  20260829T184501Z-3gwwi2twkw6e/
    fleet.json
    bootstrap/
    tunnels/
```

`current` contains only the active fleet ID. Historical fleet directories remain after teardown as evidence, but teardown removes the `current` pointer after every worker in that fleet is destroyed.

`runpod-create` also writes these generated values to the repo-local `.env`:

```text
LME_RUNPOD_FLEET_ID=<fleet-id>
LME_RUNPOD_FLEET_DIR=<absolute-path-to-current-fleet>
```

The worker pod IDs, SSH endpoints, rates, cloud tier, GPU identity, image, creation time, aggregate hourly rate, and lifecycle status are recorded in `fleet.json`.

## Invariant

Any fleet-specific producer of logs, tunnel metadata, bootstrap evidence, or other runtime artifacts must write beneath `LME_RUNPOD_FLEET_DIR`. Do not use a shared path such as:

```text
output/runpod-bootstrap-5/
output/ee-local/bootstrap/
```

for current-fleet state.

Those paths can contain valid historical evidence, but they are not authoritative for the currently managed fleet.

The fleet identity is created only after all requested pods pass RunPod readiness validation. Provisioning failures discard any partially-created fleet-state directory and roll back the newly-created pods.

A new fleet is refused while an active fleet-state pointer exists. This is intentionally fail-closed: if pods were deleted outside LME, reconcile the stale state rather than silently reusing worker names with ambiguous provenance.

This state layer is the foundation for the planned fleet bootstrap/status/tunnel UX. Those commands should consume `LME_RUNPOD_FLEET_ID` / `LME_RUNPOD_FLEET_DIR` rather than inventing their own output locations.
