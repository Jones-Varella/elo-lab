#!/bin/bash
# Faz um dump do Postgres (RDS) e envia para o S3. Roda na EC2 (Sessão 6).
set -euo pipefail
cd /opt/elo-lab
get() { grep "^$1=" .env | cut -d= -f2-; }
DATABASE_URL=$(get DATABASE_URL)
BUCKET=$(get BACKUP_BUCKET)
FILE="elo_lab_$(date -u +%Y%m%d_%H%M%S).sql.gz"

docker run --rm -e PGSSLMODE=require postgres:17-alpine \
  pg_dump "$DATABASE_URL" --no-owner --no-privileges | gzip > "/tmp/$FILE"
aws s3 cp "/tmp/$FILE" "s3://$BUCKET/postgres/$FILE"
rm -f "/tmp/$FILE"
echo "Backup enviado: s3://$BUCKET/postgres/$FILE"
