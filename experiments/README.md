# Experiments

Experiment manifests are immutable declarations of intent. Once an experiment has started, prefer creating a new manifest/version rather than changing its model set, benchmark cases, success criteria, or stop conditions in place.

Use `dispatch: matrix` for platform equivalence and `dispatch: pool` for parallel throughput.

For remote throughput campaigns, keep the authoritative scorer and source corpus on the Mac and list remote Ollama endpoints as workers. Add a `remote` label to those workers and use `required_worker_labels: [remote]` when an experiment must never fall back to the Mac. In `pool` mode, each eligible worker gets its own queue consumer, so adding remote workers increases concurrent inference without changing AdventureFinder scoring semantics.
