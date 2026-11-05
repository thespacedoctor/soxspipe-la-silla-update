#!/usr/bin/env bash
#
# Run shellcheck, then the behaviour tests in a throwaway container.
# The tests delete files in the home folder, so they only ever run in a container.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="soxspipe-la-silla-update-tests"

shellcheck "$REPO_DIR/update-pipeline.sh" "$REPO_DIR"/tests/*.sh "$REPO_DIR"/tests/stubs/*
docker build --quiet --tag "$IMAGE" "$REPO_DIR/tests" >/dev/null
docker run --rm --volume "$REPO_DIR:/repo:ro" "$IMAGE" bash /repo/tests/scenarios.sh
