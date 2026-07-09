########################################################
# Docker for Cursor Cloud Agents (DinD)
# See https://cursor.com/docs/cloud-agent/setup#running-docker
########################################################

FROM ubuntu:24.04

# Prerequisites
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    postgresql-client \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Docker
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl --retry 3 --retry-delay 5 -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y \
    docker-ce=5:28.5.2-1~ubuntu.24.04~noble \
    docker-ce-cli=5:28.5.2-1~ubuntu.24.04~noble \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    fuse-overlayfs \
    iptables \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /etc/docker && \
    printf '%s\n' '{' \
    '  "storage-driver": "fuse-overlayfs"' \
    '}' > /etc/docker/daemon.json

# Networking with Docker
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

# User and group setup for Docker + agent user
RUN id -u ubuntu &>/dev/null || useradd -m -s /bin/bash ubuntu
RUN groupadd -f docker && usermod -aG docker ubuntu
RUN usermod -aG sudo ubuntu
RUN mkdir -p /etc/sudoers.d/
RUN echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu

# Add cloudflare gpg key
RUN sudo mkdir -p --mode=0755 /usr/share/keyrings && \
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null && \
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared noble main' | sudo tee /etc/apt/sources.list.d/cloudflared.list && \
    apt-get update && \
    apt-get install -y cloudflared \
    && rm -rf /var/lib/apt/lists/*

# Node 24 + pnpm via nvm (appended last so layers above stay cached)
ENV NVM_DIR=/home/ubuntu/.nvm
ENV NODE_MAJOR=24
ENV PNPM_VERSION=11.9.0

RUN apt-get update && \
    apt-get install -y ca-certificates git openjdk-21-jre-headless && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /home/ubuntu/.nvm && chown -R ubuntu:ubuntu /home/ubuntu/.nvm && \
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.5/install.sh | NVM_DIR=/home/ubuntu/.nvm PROFILE=/dev/null bash && \
    su - ubuntu -c ". /home/ubuntu/.nvm/nvm.sh && nvm install ${NODE_MAJOR} && nvm alias default ${NODE_MAJOR} && corepack enable && corepack prepare pnpm@${PNPM_VERSION} --activate" && \
    NODE_BIN="$(su - ubuntu -c '. /home/ubuntu/.nvm/nvm.sh && dirname "$(command -v node)"')" && \
    for cmd in node pnpm corepack npx; do \
      if [ -x "${NODE_BIN}/${cmd}" ]; then ln -sf "${NODE_BIN}/${cmd}" "/usr/local/bin/${cmd}"; fi; \
    done && \
    printf '%s\n' \
      'export NVM_DIR="/home/ubuntu/.nvm"' \
      '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' \
      'export PATH="$(dirname "$(nvm which 24)"):$PATH"' \
      > /etc/profile.d/ownet-node.sh

# Non-interactive bash (agent shell commands) sources BASH_ENV before each script.
ENV BASH_ENV=/etc/profile.d/ownet-node.sh
