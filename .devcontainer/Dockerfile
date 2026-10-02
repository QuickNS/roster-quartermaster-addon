FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG STYLUA_VERSION=2.5.2
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 python3-venv lua5.1 lua-check lua-filesystem curl unzip ca-certificates git \
    && apt-get clean
RUN case "$(uname -m)" in \
        x86_64) target=x86_64 ;; \
        aarch64) target=aarch64 ;; \
        *) echo "Unsupported StyLua architecture" >&2; exit 1 ;; \
    esac \
    && curl -fLsS "https://github.com/JohnnyMorganz/StyLua/releases/download/v${STYLUA_VERSION}/stylua-linux-${target}.zip" -o /tmp/stylua.zip \
    && unzip /tmp/stylua.zip -d /usr/local/bin \
    && chmod +x /usr/local/bin/stylua \
    && rm /tmp/stylua.zip
USER vscode
