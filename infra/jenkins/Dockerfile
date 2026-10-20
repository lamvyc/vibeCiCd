# Derived Jenkins controller image for the local lab.
#
# Base: the exact official Jenkins LTS release matching the existing WAR data
# (2.580.1, JDK 21, arm64). Tools are copied from the corresponding official
# upstream images; no third-party base image replaces the Jenkins image.
#
# Build (from repo root):
#   docker build --network host \
#     --build-arg HTTP_PROXY=http://192.168.5.2:7897 \
#     --build-arg HTTPS_PROXY=http://192.168.5.2:7897 \
#     --build-arg NO_PROXY=localhost,127.0.0.1,::1,192.168.5.1 \
#     -f infra/jenkins/Dockerfile -t vibe-cicd/jenkins:2.580.1-tools-1 .

FROM node:24.18.0-trixie-slim@sha256:ae91dcc111a68c9d2d81ff2a17bda61be126426176fde6fe7d08ab13b7f50573 AS node
FROM golang:1.27.2-trixie@sha256:47667934874913a449b96faa7ef4777fa285d9ec29126ee80ed61c45b7cccf0e AS go
FROM docker:29.9.1-cli@sha256:6fae2214c3121a28d5aa639d09032f61310b7c9c75ffbad1025f261a1b621800 AS dockercli

FROM jenkins/jenkins:2.580.1-lts-jdk21@sha256:a660310e39ade10631f774bacd5219de767dfd08947ea5c32a739b5e5bb382c1

USER root
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY
ENV http_proxy=${HTTP_PROXY} \
    https_proxy=${HTTPS_PROXY} \
    no_proxy=${NO_PROXY} \
    HTTP_PROXY=${HTTP_PROXY} \
    HTTPS_PROXY=${HTTPS_PROXY} \
    NO_PROXY=${NO_PROXY} \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl jq xz-utils make file procps libstdc++6 \
 && rm -rf /var/lib/apt/lists/*

# Node/npm/corepack from the exact official Node image (Debian trixie).
# Only the node binary is copied directly; npm/npx/corepack are relative
# symlinks in the official image, so they are re-created below (a plain COPY
# would dereference them and break their module resolution).
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -sf ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
 && ln -sf ../lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack
ENV COREPACK_HOME=/usr/local/share/corepack
RUN mkdir -p "$COREPACK_HOME" \
 && corepack enable \
 && corepack prepare pnpm@9.15.0 --activate \
 && pnpm --version

# Go toolchain from the exact official Go image.
COPY --from=go /usr/local/go /usr/local/go
ENV GOROOT=/usr/local/go \
    PATH=/usr/local/go/bin:/opt/java/openjdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Static CLI tools, pinned by version and SHA256.
ARG KUBECTL_VERSION=v1.35.9
ARG KUBECTL_SHA256=39c98bca82875d9a9ddfb6f3c5ab17c3f78ea0801230683e538a67d5c053308d
RUN curl -fsSLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/arm64/kubectl" \
 && echo "${KUBECTL_SHA256}  /usr/local/bin/kubectl" | sha256sum -c - \
 && chmod 0755 /usr/local/bin/kubectl

ARG KUSTOMIZE_VERSION=v5.8.3
ARG KUSTOMIZE_SHA256=9867b76482cfc6d25b546abc1d2b5a32bd137505aba640649b4b378f64f6d68f
RUN curl -fsSLo /tmp/kustomize.tar.gz \
      "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_arm64.tar.gz" \
 && echo "${KUSTOMIZE_SHA256}  /tmp/kustomize.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/kustomize.tar.gz -C /usr/local/bin \
 && chmod 0755 /usr/local/bin/kustomize \
 && rm -f /tmp/kustomize.tar.gz

# Docker CLI only; builds use the VM's Docker daemon over /var/run/docker.sock.
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
RUN chmod 0755 /usr/local/bin/docker

# Do not persist the build-time proxy into the image.
ENV http_proxy= https_proxy= no_proxy= HTTP_PROXY= HTTPS_PROXY= NO_PROXY=

USER jenkins
LABEL org.opencontainers.image.title="vibe-cicd Jenkins tools" \
      org.opencontainers.image.description="Official Jenkins 2.580.1 LTS + pinned build tools" \
      org.opencontainers.image.version="2.580.1-tools-1" \
      org.opencontainers.image.base.name="jenkins/jenkins:2.580.1-lts-jdk21"
