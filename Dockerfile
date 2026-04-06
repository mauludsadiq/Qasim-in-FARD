# Stage 1: Build fardrun from source
FROM rust:1.76-slim AS builder

WORKDIR /build

# Copy FARD source
COPY fard_src/ .

# Build release binary
RUN cargo build --release --bin fardrun

# Stage 2: Runtime image
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Copy fardrun binary
COPY --from=builder /build/target/release/fardrun /usr/local/bin/fardrun

# Copy Qasim source
WORKDIR /app
COPY main.fard .
COPY packages/ packages/

# Data directory for SQLite DB and fardrun output
RUN mkdir -p /data /tmp/qasim

# Port
EXPOSE 9801

# QASIM_CHAIN_SECRET_HEX must be provided at runtime
ENV QASIM_DB_PATH=/data/qasim.db

ENTRYPOINT ["fardrun", "run", "--program", "main.fard", "--out", "/tmp/qasim"]
