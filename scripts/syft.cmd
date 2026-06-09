@echo off
REM Docker wrapper for Syft — routes `syft ...` to the anchore/syft container.
REM Mounts the current directory at /work so `syft dir:.` and output paths resolve.
docker run --rm -v "%CD%:/work" -w /work anchore/syft:latest %*
