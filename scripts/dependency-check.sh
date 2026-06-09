#!/usr/bin/env sh
# Docker wrapper for OWASP Dependency-Check — routes `dependency-check ...` to the container.
# Fallback path: Day 1's skill prefers the Maven plugin (mvn org.owasp:dependency-check-maven:check);
# this wrapper is for direct CLI use. Project mounts at /src; NVD data cached in a named volume.
# Pass an NVD API key (recommended) by setting NVD_API_KEY in your environment.
exec docker run --rm -v depscan-dc-data:/usr/share/dependency-check/data -v "$PWD:/src" -w /src -e NVD_API_KEY="${NVD_API_KEY:-}" owasp/dependency-check:latest "$@"
