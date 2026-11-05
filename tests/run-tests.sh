#!/usr/bin/env bash
#
# RUN SHELLCHECK, THEN THE BEHAVIOUR TESTS IN A THROWAWAY CONTAINER.
# THE TESTS DELETE FILES IN THE HOME FOLDER, SO THEY ONLY EVER RUN IN A CONTAINER.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="soxspipe-la-silla-update-tests"

shellcheck "$REPO_DIR/update-pipeline.sh" "$REPO_DIR"/tests/*.sh "$REPO_DIR"/tests/stubs/*
docker build --quiet --tag "$IMAGE" "$REPO_DIR/tests" >/dev/null
docker run --rm --volume "$REPO_DIR:/repo:ro" "$IMAGE" bash /repo/tests/scenarios.sh
