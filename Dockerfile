# NimClaw — multi-stage build
# Stage 1: Build Nim binary + Go channel CLIs
# Stage 2: Minimal runtime — just the binaries + curl/TLS

# ── Builder ──────────────────────────────────────────────────────
FROM nimlang/nim:2.2.8 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    golang-go git ca-certificates libcurl4-openssl-dev libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY . .

# Install Nim dependencies
RUN nimble install -y --depsOnly

# Build NimClaw binary
RUN nimble build -y

# Build Go channel CLIs
RUN cd channels/lark-cli && go build -o ../bin/lark-cli . || true
RUN cd channels/nkn-cli && go build -o ../bin/nkn-cli . || true

# ── Runtime ──────────────────────────────────────────────────────
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    libcurl4 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /nimclaw

# Copy built binaries
COPY --from=builder /build/nimclaw ./nimclaw
COPY --from=builder /build/channels/bin/ ./channels/bin/

# Copy runtime assets
COPY templates/ ./templates/
COPY skills/ ./skills/
COPY plugins/ ./plugins/

# Default config volume mount point
VOLUME /data

ENV NIMCLAW_DIR=/data
ENV PATH="/nimclaw:/nimclaw/channels/bin:${PATH}"

EXPOSE 18790

ENTRYPOINT ["./nimclaw"]
CMD ["service", "run"]
