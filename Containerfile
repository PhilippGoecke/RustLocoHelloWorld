FROM debian:trixie-slim as builder

ARG DEBIAN_FRONTEND=noninteractive

# install rustup dependencies
RUN apt update && apt upgrade -y \
  # install dependencies
  && apt install -y --no-install-recommends --no-install-suggests gcc libc6-dev curl ca-certificates pkg-config libssl-dev \
  # install rustup
  && apt install -y --no-install-recommends --no-install-suggests rustup \
  && rm -rf "/var/lib/apt/lists/*" \
  && rm -rf /var/cache/apt/archives

# add user and set home directory
ARG USER=rust
RUN useradd --create-home --shell /bin/bash $USER
ARG HOME="/home/$USER"
WORKDIR $HOME
USER $USER

ENV PATH="$HOME/.cargo/bin:$PATH"

RUN rustup update \
  # && rustup self update \
  && rustup default stable \
  && rustc --version

WORKDIR /app

# Install the loco and scaffold a minimal "hello world" app
RUN cargo install loco --locked \
  && cargo install sea-orm-cli --locked \
  && loco new --name hello_world --db sqlite --bg async --assets none

WORKDIR /app/hello_world

RUN cargo loco generate controller welcome -- --kind api index

# Capture the Rust, cargo and loco versions used to build this image
RUN rustc --version | awk '{print $2}' > /app/hello_world/.rust_version \
  && cargo --version | awk '{print $2}' > /app/hello_world/.cargo_version \
  && loco --version | awk '{print $2}' > /app/hello_world/.loco_version

# Replace the welcome controller with a "Hello World" / "Hello $name!" handler mounted at "/"
RUN cat > src/controllers/welcome.rs <<'EOF'
use loco_rs::prelude::*;
use serde::Deserialize;

const RUST_VERSION: &str = include_str!("../../.rust_version");
const CARGO_VERSION: &str = include_str!("../../.cargo_version");
const LOCO_VERSION: &str = include_str!("../../.loco_version");

#[derive(Debug, Deserialize)]
pub struct HelloParams {
    pub name: Option<String>,
}

async fn index(Query(params): Query<HelloParams>) -> Result<Response> {
    let greeting = match params.name {
        Some(name) if !name.is_empty() => format!("Hello {name}!"),
        _ => "Hello World".to_string(),
    };
    let body = format!(
        "{greeting}\nrust: {}\ncargo: {}\nloco: {}\n",
        RUST_VERSION.trim(),
        CARGO_VERSION.trim(),
        LOCO_VERSION.trim()
    );
    format::text(&body)
}

pub fn routes() -> Routes {
    Routes::new().add("/", get(index))
}
EOF

# RUN cargo loco start

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
COPY --from=builder --chown=$USER:$USER /app/hello_world/target/release/hello_world-cli /usr/local/bin/hello_world
COPY --from=builder --chown=$USER:$USER /app/hello_world/config ./config

RUN cp config/development.yaml config/production.yaml \
  && sed -i 's/binding: localhost/binding: 0.0.0.0/g' config/production.yaml

EXPOSE 5150

ENV LOCO_ENV=production

CMD ["hello_world", "start"]
