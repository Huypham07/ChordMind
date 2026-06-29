# ponytail: serves a pre-built Flutter web bundle via nginx.
# Run `flutter build web` in app/ before `docker compose build` so build/web exists.
# (A full in-image Flutter build is possible but the SDK image is huge — not worth it yet.)
FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY build/web /usr/share/nginx/html
