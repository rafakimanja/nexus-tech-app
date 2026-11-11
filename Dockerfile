# Compile a aplicação; a imagem final contém apenas o Nginx e os arquivos web.
ARG FLUTTER_IMAGE=ghcr.io/cirruslabs/flutter:stable
FROM ${FLUTTER_IMAGE} AS build

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
ARG APP_BACKEND=api
ARG API_BASE_URL
ARG GOOGLE_WEB_CLIENT_ID
RUN set -eu; \
    set -- --release "--dart-define=APP_BACKEND=${APP_BACKEND}"; \
    if [ -n "${API_BASE_URL}" ]; then set -- "$@" "--dart-define=API_BASE_URL=${API_BASE_URL}"; fi; \
    if [ -n "${GOOGLE_WEB_CLIENT_ID}" ]; then set -- "$@" "--dart-define=GOOGLE_WEB_CLIENT_ID=${GOOGLE_WEB_CLIENT_ID}"; fi; \
    flutter build web "$@"

FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web/ /usr/share/nginx/html/
EXPOSE 80
