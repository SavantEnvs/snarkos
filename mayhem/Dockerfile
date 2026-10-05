# syntax=docker/dockerfile:1.7
#
# snarkOS commit-image Dockerfile — Rust cargo-fuzz on the org base (ghcr.io/savantenvs/base).
# Installs a pinned nightly + cargo-fuzz + upstream's MSRV (1.88, pinned via rust-toolchain.toml)
# into a fixed, $HOME-independent prefix (/opt/toolchains/rust — SPEC §6.2 item 8).

FROM ghcr.io/savantenvs/base:20260621

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH

ARG SANITIZER_FLAGS
ARG MAYHEM_JOBS=

ARG RUST_TOOLCHAIN=nightly-2025-09-05
ARG CARGO_FUZZ_VERSION=0.12.0

ENV RUSTUP_HOME=/opt/toolchains/rust/rustup \
    CARGO_HOME=/opt/toolchains/rust/cargo \
    PATH=/opt/toolchains/rust/cargo/bin:$PATH
ENV LIBCLANG_PATH=/usr/lib/llvm-19/lib

USER root
RUN set -eux; \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libclang-dev && rm -rf /var/lib/apt/lists/*; \
    set -eux; \
    install -d /opt/toolchains/rust; \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --no-modify-path --profile minimal --default-toolchain "$RUST_TOOLCHAIN"; \
    rustup component add rust-src --toolchain "$RUST_TOOLCHAIN"; \
    rustup toolchain install 1.88; rustup component add rust-std clippy rustfmt --toolchain 1.88; \
    cargo install cargo-fuzz --version "$CARGO_FUZZ_VERSION" --locked; \
    chown -R 2000:2000 /opt/toolchains/rust; \
    rustc --version; cargo --version; cargo fuzz --version; rustc +1.88 --version
USER mayhem

WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
