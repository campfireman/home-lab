FROM node:18-slim AS ui-builder
WORKDIR /src
RUN apt-get update && apt-get install -y git
RUN git clone https://github.com/cooklang/cookcli.git .
RUN npm install && npm run build-css

FROM rust:1.92-trixie AS builder
WORKDIR /app
COPY --from=ui-builder /src .
RUN cargo build --release

FROM rust:1.92-trixie

COPY --from=builder /app/target/release/cook /usr/local/bin/cook

WORKDIR /recipes
EXPOSE 9080
ENTRYPOINT ["cook", "server", "--host"]
