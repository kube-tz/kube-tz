# syntax=docker/dockerfile:1

ARG ALPINE_VERSION=3.24

# ---------------------------------------------------------------------------
# Stage 1: build the tz database and assemble a tiny static copy toolkit
# ---------------------------------------------------------------------------
FROM alpine:${ALPINE_VERSION} AS src

ARG tzdbversion=2026e
# Optional: pin the tarball checksum for reproducible, verified builds.
#   docker build --build-arg tzdbsha256=<sha256 of tzdb-<version>.tar.lz> .
ARG tzdbsha256=""
# posix_only = standard zoneinfo only (no right/ leap-second tree), roughly half the size.
ARG REDO=posix_only

RUN apk add --no-cache build-base lzip busybox-static && \
    wget -q -O tzdb.tar.lz "https://data.iana.org/time-zones/releases/tzdb-${tzdbversion}.tar.lz" && \
    if [ -n "${tzdbsha256}" ]; then echo "${tzdbsha256}  tzdb.tar.lz" | sha256sum -c -; fi && \
    lzip -cd tzdb.tar.lz | tar -xf - && \
    mv tzdb-* tzdb && \
    make -C tzdb TOPDIR=/build REDO="${REDO}" install

# Static busybox providing exactly what the kube-tz init script needs: sh + cp.
RUN mkdir -p /rootfs/bin && \
    cp /bin/busybox.static /rootfs/bin/busybox && \
    ln -s busybox /rootfs/bin/sh && \
    ln -s busybox /rootfs/bin/cp

# ---------------------------------------------------------------------------
# Stage 2: final image (no package manager, no libc, nothing else)
# ---------------------------------------------------------------------------
FROM scratch

ARG tzdbversion=2026e

LABEL org.opencontainers.image.title="kube-tz" \
      org.opencontainers.image.description="tz database plus a static copy toolkit for the kube-tz Helm chart init container" \
      org.opencontainers.image.version="${tzdbversion}"

# sh + cp (static busybox)
COPY --from=src /rootfs/bin /bin
# zoneinfo at the chart's default image.zoneInfoPath
COPY --from=src /build/usr/share/zoneinfo /opt/tzdata/usr/share/zoneinfo

ENV PATH=/bin
# Matches the chart's default init securityContext (runAsUser/runAsGroup 65532).
USER 65532:65532