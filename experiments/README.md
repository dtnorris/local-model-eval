# Experiments

Experiment manifests are immutable declarations of intent. Once an experiment has started, prefer creating a new manifest/version rather than changing its model set, benchmark cases, success criteria, or stop conditions in place.

Use `dispatch: matrix` for platform equivalence and `dispatch: pool` for parallel throughput.
