#!/usr/bin/env sh
# Docker wrapper for Grype — routes `grype ...` to the anchore/grype container.
# Mounts the current directory at /work so relative paths (e.g. sbom:target/sbom.cdx.json) resolve.
# Caches the vulnerability DB in a named volume so it is not re-downloaded every run.
exec docker run --rm -e GRYPE_DB_CACHE_DIR=/grypedb -v depscan-grype-db:/grypedb -v "$PWD:/work" -w /work anchore/grype:latest "$@"
