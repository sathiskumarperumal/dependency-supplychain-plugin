@echo off
REM Docker wrapper for OWASP Dependency-Check — routes `dependency-check ...` to the container.
REM Fallback path: Day 1's skill prefers the Maven plugin (mvn org.owasp:dependency-check-maven:check);
REM this wrapper is for direct CLI use. Project mounts at /src; NVD data cached in a named volume.
REM Pass an NVD API key (recommended) by setting NVD_API_KEY in your environment.
docker run --rm -v depscan-dc-data:/usr/share/dependency-check/data -v "%CD%:/src" -w /src -e NVD_API_KEY=%NVD_API_KEY% owasp/dependency-check:latest %*
