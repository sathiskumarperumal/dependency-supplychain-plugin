#!/usr/bin/env sh
# Docker wrapper for Syft — routes `syft ...` to the anchore/syft container.
# Mounts the current directory at /work so `syft dir:.` and output paths resolve.
exec docker run --rm -v "$PWD:/work" -w /work anchore/syft:latest "$@"
