#!/bin/bash
# Atualiza a aplicação na EC2. Uso: bash scripts/deploy.sh [tag-da-imagem]
# Roda na própria EC2 (manualmente na Sessão 4, pelo GitHub Actions na Sessão 5).
set -euo pipefail
cd /opt/elo-lab
REGION="${AWS_REGION:-us-east-2}"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
export ECR_REGISTRY="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"
export IMAGE_TAG="${1:-latest}"

echo ">> Lendo segredos do Secrets Manager"
aws secretsmanager get-secret-value --region "$REGION" --secret-id elo-lab/prod \
  --query SecretString --output text | jq -r 'to_entries[] | "\(.key)=\(.value)"' > .env
chmod 600 .env

echo ">> Baixando imagens ($IMAGE_TAG)"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d --remove-orphans
docker image prune -f

echo ">> Verificando saúde"
curl -fsS --retry 10 --retry-delay 3 --retry-all-errors http://localhost/health
echo
echo ">> Deploy concluído"
