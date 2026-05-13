FROM debian:trixie-slim as builder

ARG DEBIAN_FRONTEND=noninteractive
ENV RUSTUP_HOME=/usr/local/rustup
ENV CARGO_HOME=/usr/local/cargo
ENV PATH=/usr/local/cargo/bin:$PATH

# install dependencies
RUN apt update && apt upgrade -y \
  && apt install -y --no-install-recommends --no-install-suggests ca-certificates build-essential ca-certificates curl pkg-config libssl-dev git \
  && rm -rf "/var/lib/apt/lists/*" \
  && rm -rf /var/cache/apt/archives

# add user and set home directory
ARG USER=rust
RUN useradd --create-home --shell /bin/bash $USER
ARG HOME="/home/$USER"
WORKDIR $HOME
USER $USER

WORKDIR /app

# Install the loco CLI and scaffold a minimal "hello world" app
RUN cargo install loco-cli loco \
  && loco new --name hello_world --template lightweight-service --db sqlite --bg async --assets none

WORKDIR /app/hello_world

# Pre-build dependencies to leverage Docker layer cache
RUN cargo build --release

# new stage for Rails app
FROM debian:trixie-slim as runtime

# install dependencies
RUN apt update && apt upgrade -y \
  && apt install -y --no-install-recommends --no-install-suggests ca-certificates libssl3 sqlite3 \
  && rm -rf "/var/lib/apt/lists/*" \
  && rm -rf /var/cache/apt/archives

# add user and set home directory
ARG USER=rust
RUN useradd --create-home --shell /bin/bash $USER
ARG HOME="/home/$USER"
WORKDIR $HOME
USER $USER

WORKDIR /srv/app

# Copy compiled binary and config from the builder
COPY --from=builder /app/hello_world/target/release/hello_world-cli /usr/local/bin/hello_world
COPY --from=builder /app/hello_world/config ./config

EXPOSE 5150

CMD ["hello_world", "start"]
