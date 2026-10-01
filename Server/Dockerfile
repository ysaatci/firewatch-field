# Simulator server image. Build from the repository root:
#   docker build -f Server/Dockerfile -t firewatch-simulator .

# ---- Build ----
FROM swift:6.3-noble AS build
# The directory name matters: the Server package refers to the root package by path,
# and SwiftPM names path dependencies after their directory.
WORKDIR /build/firewatch-field
COPY Package.swift Package.resolved ./
COPY Sources ./Sources
COPY Server/Package.swift Server/Package.resolved* ./Server/
RUN swift package --package-path Server resolve
# Tests are copied only because the manifest declares the test target.
COPY Server/Sources ./Server/Sources
COPY Server/Tests ./Server/Tests
RUN swift build --package-path Server -c release --product firewatch-server --static-swift-stdlib \
    && mkdir /staging \
    && cp "$(swift build --package-path Server -c release --show-bin-path)/firewatch-server" /staging/

# ---- Run ----
FROM ubuntu:noble
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --home-dir /app simulator
WORKDIR /app
COPY --from=build /staging/firewatch-server .
USER simulator
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s CMD curl -fsS http://localhost:8080/health || exit 1
ENTRYPOINT ["./firewatch-server"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
