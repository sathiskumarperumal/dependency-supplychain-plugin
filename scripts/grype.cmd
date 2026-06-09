@echo off
REM Docker wrapper for Grype — routes `grype ...` to the anchore/grype container.
REM Mounts the current directory at /work so relative paths (e.g. sbom:target/sbom.cdx.json) resolve.
REM Caches the vulnerability DB in a named volume so it is not re-downloaded every run.
docker run --rm -e GRYPE_DB_CACHE_DIR=/grypedb -v depscan-grype-db:/grypedb -v "%CD%:/work" -w /work anchore/grype:latest %*
