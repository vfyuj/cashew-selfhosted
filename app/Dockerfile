# Builds and serves the Flutter web app -- the actual UI, separate from the
# API in /server (see docker-compose.yml, DEPLOYMENT.md). Rebuilt from
# source on every `docker compose up --build`, so there's never a manual
# "build locally and copy the files over" step to remember on redeploys.
FROM ghcr.io/cirruslabs/flutter:3.19.6 AS build
WORKDIR /app
COPY . .
RUN flutter pub get
RUN flutter build web --release

FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
