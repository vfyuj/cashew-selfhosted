FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart pub get --offline
RUN dart compile exe bin/server.dart -o bin/server
RUN dart compile exe bin/create_user.dart -o bin/create_user

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends libsqlite3-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/bin/server /app/bin/server
COPY --from=build /app/bin/create_user /app/bin/create_user
WORKDIR /app
ENV PORT=8080
EXPOSE 8080
VOLUME ["/data"]
ENTRYPOINT ["/app/bin/server"]
