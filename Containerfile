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

# Install Rust toolchain (rustup + cargo) into the shared CARGO_HOME/RUSTUP_HOME
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --default-toolchain stable \
  && chmod -R a+w $RUSTUP_HOME $CARGO_HOME

# add user and set home directory
ARG USER=rust
RUN useradd --create-home --shell /bin/bash $USER
ARG HOME="/home/$USER"
WORKDIR $HOME
USER $USER

WORKDIR /app

# Install the loco and scaffold a minimal "hello world" app
RUN cargo install loco \
  && loco new --name hello_world --db sqlite --bg async --assets none

WORKDIR /app/hello_world

RUN cargo loco generate controller welcome index

# Replace the welcome controller with a "Hello World" / "Hello $name!" handler mounted at "/"
RUN cat > src/controllers/welcome.rs <<'EOF'
use loco_rs::prelude::*;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct HelloParams {
    pub name: Option<String>,
}

async fn index(Query(params): Query<HelloParams>) -> Result<Response> {
    let body = match params.name {
        Some(name) if !name.is_empty() => format!("Hello {name}!"),
        _ => "Hello World".to_string(),
    };
    format::text(&body)
}

pub fn routes() -> Routes {
    Routes::new().add("/", get(index))
}
EOF

# Pre-build dependencies to leverage Docker layer cache
RUN cargo build --release

# new stage for Rust app
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

#ENV LOCO_ENV=production

CMD ["hello_world", "start", "--binding", "0.0.0.0"]
