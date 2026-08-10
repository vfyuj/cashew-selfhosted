# Single image: the Dart API also serves the compiled Flutter web build
# (see server/lib/src/web_handler.dart), so there's one container, one
# port, and the browser only ever sees one origin -- no reverse-proxy path
# splitting, no CORS. Two build stages because the API and the web UI use
# different toolchains, not because they end up in different containers.
FROM ghcr.io/cirruslabs/flutter:3.19.6 AS web-build
WORKDIR /web
COPY app/ .
RUN flutter pub get
# Default ("auto") renderer, deliberately: --web-renderer html was tried and
# reverted because the owner disliked how it rendered. See
# specs/03-stage-1-kill-google.md.
#
# FLUTTER_WEB_CANVASKIT_URL points the engine at the CanvasKit copy Flutter
# already writes into build/web/canvaskit/. Without it the CanvasKit renderer
# fetches canvaskit.js -- several MB -- from www.gstatic.com on every launch.
# That was the large, blocking Google request, and it stays fixed here.
RUN flutter build web --release \
      --dart-define=FLUTTER_WEB_CANVASKIT_URL=/canvaskit/

# Pre-compress everything worth compressing, keeping the original beside it
# (-k) for clients that don't accept gzip. server/lib/src/web_handler.dart
# serves the .gz when the request allows it.
#
# Done here, once per image build, rather than per request: the target is a
# Raspberry Pi, and gzipping a 7.6 MB main.dart.js on every page load would
# swap a bandwidth cost for a worse CPU one. Whole build is ~39 MB raw against
# ~12 MB gzipped.
#
# Skips files under 1k (the header outweighs the saving) and formats that are
# already compressed (png/jpg/webp/woff2/ico) -- gzipping those grows them.
RUN find build/web -type f -size +1k \
      \( -name '*.js'    -o -name '*.json' -o -name '*.css' \
      -o -name '*.html'  -o -name '*.wasm' -o -name '*.ttf' \
      -o -name '*.otf'   -o -name '*.svg'  -o -name '*.map' \
      -o -name '*.symbols' \
      -o -name 'NOTICES' \) \
      -exec gzip -9 -k {} +

FROM dart:stable AS server-build
WORKDIR /server
COPY server/pubspec.* ./
RUN dart pub get
COPY server/ .
RUN dart pub get --offline
RUN dart compile exe bin/server.dart -o bin/server
RUN dart compile exe bin/create_user.dart -o bin/create_user

FROM debian:bookworm-slim
# curl is here for the container healthcheck in docker-compose.yml (and is
# handy for poking /health from inside the container when debugging).
RUN apt-get update \
    && apt-get install -y --no-install-recommends libsqlite3-dev ca-certificates curl \
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
