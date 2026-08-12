# Single image: the Dart API also serves the compiled Flutter web build
# (see server/lib/src/web_handler.dart), so there's one container, one
# port, and the browser only ever sees one origin -- no reverse-proxy path
# splitting, no CORS. Two build stages because the API and the web UI use
# different toolchains, not because they end up in different containers.
# Deliberately no `--platform=$BUILDPLATFORM` on this stage, tempting as it is:
# the web build's output is arch-neutral, so pinning it to the build host would
# avoid emulating it in a cross build. But $BUILDPLATFORM only exists under
# BuildKit, and the legacy builder fails to parse the line at all -- which would
# break `docker compose up --build` on any host whose Docker lacks buildx, and
# that command is the operator's whole deploy loop. release.yml builds each
# architecture on its own native runner instead, so nothing is emulated anyway.
FROM ghcr.io/cirruslabs/flutter:3.19.6 AS web-build
WORKDIR /web
COPY app/ .
RUN flutter pub get
# CanvasKit everywhere, pinned -- do not go back to the default "auto".
#
# "auto" does not mean "pick the best one"; it means `useCanvasKit = isDesktop`
# (flutter_web_sdk/lib/_engine/engine/renderer.dart in the pinned 3.19.6 SDK).
# A phone browser is not desktop, so auto quietly served **the html renderer to
# every phone** while desktop got CanvasKit -- two different rendering engines
# for the same deploy, and only the desktop one was ever looked at. That is the
# renderer specs/03-stage-1-kill-google.md records the owner rejecting on looks;
# iPhone Safari had been getting it all along, and got a repeatable WebContent
# crash on the budgets tab with it. Pinning canvaskit makes the phone render
# exactly what the desktop does.
#
# FLUTTER_WEB_CANVASKIT_URL points the engine at the CanvasKit copy Flutter
# already writes into build/web/canvaskit/. Without it the CanvasKit renderer
# fetches canvaskit.js -- several MB -- from www.gstatic.com on every launch.
# That was the large, blocking Google request, and it stays fixed here. It
# matters more now than it did under auto: every client takes this path, not
# just desktop ones.
RUN flutter build web --release \
      --web-renderer canvaskit \
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
# Must match the VOLUME below. Both binaries default DATA_DIR to './data'
# (server.dart, create_user.dart), which against WORKDIR /app resolves to
# /app/data -- inside the container's writable layer, not the volume. That
# default is right for local `dart run` and wrong for every image, so it is
# overridden here rather than in the code. docker-compose.yml also sets it
# explicitly, which is why the compose path was never affected; a bare
# `docker run -v cashew-data:/data` had no such backstop, and wrote a
# database that vanished on the next pull-and-recreate.
ENV DATA_DIR=/data
EXPOSE 8080
VOLUME ["/data"]
ENTRYPOINT ["/app/bin/server"]
