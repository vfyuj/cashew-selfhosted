# Single image: the Dart API also serves the compiled Flutter web build
# (see server/lib/src/web_handler.dart), so there's one container, one
# port, and the browser only ever sees one origin -- no reverse-proxy path
# splitting, no CORS. Two build stages because the API and the web UI use
# different toolchains, not because they end up in different containers.
FROM ghcr.io/cirruslabs/flutter:3.19.6 AS web-build
WORKDIR /web
COPY app/ .
RUN flutter pub get
RUN flutter build web --release

FROM dart:stable AS server-build
WORKDIR /server
COPY server/pubspec.* ./
RUN dart pub get
COPY server/ .
RUN dart pub get --offline
RUN dart compile exe bin/server.dart -o bin/server
RUN dart compile exe bin/create_user.dart -o bin/create_user

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends libsqlite3-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=server-build /server/bin/server /app/bin/server
COPY --from=server-build /server/bin/create_user /app/bin/create_user
COPY --from=web-build /web/build/web /app/web
WORKDIR /app
ENV PORT=8080
ENV WEB_DIR=/app/web
EXPOSE 8080
VOLUME ["/data"]
ENTRYPOINT ["/app/bin/server"]
