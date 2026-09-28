# Agent instructions

This repository packages WordPress with SQLite on FrankenPHP. The Elementor, Pro Elements, and hello-elementor components are optional build variants.

Read `README.md` for supported build arguments, local run examples, environment variables, volumes, and published image tags. Check `Dockerfile`, `entrypoint.sh`, and `docker-compose.yml` when changing image or runtime behavior.

`.github/workflows/docker-publish.yml` publishes both multi-architecture image variants to Docker Hub on pushes to `main` and `v*` tags, and can also be started manually. Treat those triggers as releases; do not use the publish workflow for routine validation.

The repository has no tracked test suite or pull-request CI workflow. For image or runtime changes, use the README's local Docker build and run examples with disposable credentials and data, then report the commands actually run. For documentation-only changes, `git diff --check` is sufficient; do not claim a container build or runtime check unless it was performed.
