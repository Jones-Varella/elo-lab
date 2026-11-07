#!/bin/bash
# User data da EC2 (Sessão 3). Roda uma vez, como root, quando a máquina é criada.
# TROQUE "SEU_USUARIO" pelo seu usuário do GitHub antes de colar.
set -euxo pipefail
REPO_URL="https://github.com/SEU_USUARIO/elo-lab.git"

dnf install -y docker git jq
systemctl enable --now docker

# Plugins do Docker: compose e buildx
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL https://github.com/docker/compose/releases/download/v2.32.4/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
curl -fsSL https://github.com/docker/buildx/releases/download/v0.19.3/buildx-v0.19.3.linux-amd64 \
  -o /usr/local/lib/docker/cli-plugins/docker-buildx
chmod +x /usr/local/lib/docker/cli-plugins/*

# 2 GB de swap: dá folga para a máquina pequena
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile swap swap defaults 0 0' >> /etc/fstab

git clone "$REPO_URL" /opt/elo-lab
