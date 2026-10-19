# Build context is prepared by CI in .runtime/image-context:
#   server  - statically linked linux/arm64 Go binary
#   static/ - built lowCode-platform playground dist
# No base image is used, so Docker Hub is not required.
FROM scratch

ARG APP_VERSION=dev
ARG GIT_COMMIT=unknown
ARG BUILD_TIME=unknown

LABEL org.opencontainers.image.title="lowcode-platform-web" \
      org.opencontainers.image.description="Static lowCode-platform SPA served by a Go static server" \
      org.opencontainers.image.source="http://localhost:3000/lowcode/vibe-cicd" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.created="${BUILD_TIME}"

COPY server /server
COPY static /static

ENV STATIC_DIR=/static \
    LISTEN_ADDR=:8080 \
    APP_ENV=prod \
    APP_VERSION=${APP_VERSION} \
    GIT_COMMIT=${GIT_COMMIT} \
    BUILD_TIME=${BUILD_TIME}

USER 65532:65532
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 CMD ["/server", "-healthcheck"]

ENTRYPOINT ["/server"]
