# syntax=docker/dockerfile:1

# ── Stage 1: Build ──────────────────────────────────────────────────
FROM rust:1-slim-bookworm AS builder

ARG BUILD_REF=v0.5.7
ARG RUSTFLAGS=""
ARG CARGO_PROFILE=release

RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates pkg-config libssl-dev build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone https://github.com/RightNow-AI/openfang.git . && \
    git checkout "${BUILD_REF}"

# Fix: rmcp made StreamableHttpClientTransportConfig #[non_exhaustive],
# so struct literal syntax no longer compiles from downstream crates.
RUN perl -0777 -i -pe \
    's/let config = StreamableHttpClientTransportConfig \{\s*uri: Arc::from\(url\),\s*custom_headers,\s*\.\.Default::default\(\)\s*\};/let mut config = StreamableHttpClientTransportConfig::default();\n        config.uri = Arc::from(url);\n        config.custom_headers = custom_headers;/s' \
    crates/openfang-runtime/src/mcp.rs

ENV RUSTFLAGS="${RUSTFLAGS}"
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    cargo build --profile "${CARGO_PROFILE}" -p openfang-cli \
    && cp target/"${CARGO_PROFILE}"/openfang /usr/local/bin/openfang

# ── Stage 2: Runtime ────────────────────────────────────────────────
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl \
        python3 python3-pip python3-venv \
        nodejs npm \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/openfang /usr/local/bin/openfang

ENV OPENFANG_HOME=/data
ENV OPENFANG_LISTEN=0.0.0.0:4200
VOLUME /data
EXPOSE 4200

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost:4200/api/health || exit 1

CMD ["openfang", "start"]
