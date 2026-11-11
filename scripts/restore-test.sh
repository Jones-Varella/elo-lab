#!/bin/bash
# Restaura o backup mais recente num banco separado (restore_test) e confere os dados.
# Não toca no banco principal. Uso: bash scripts/restore-test.sh [arquivo.sql.gz]
set -euo pipefail
cd /opt/elo-lab
get() { grep "^$1=" .env | cut -d= -f2-; }
DATABASE_URL=$(get DATABASE_URL)
BUCKET=$(get BACKUP_BUCKET)
KEY="${1:-$(aws s3 ls "s3://$BUCKET/postgres/" | sort | tail -1 | awk '{print $4}')}"
TEST_URL=$(echo "$DATABASE_URL" | sed -E 's#/([^/?]+)(\?|$)#/restore_test\2#')
PSQL="docker run --rm -i -e PGSSLMODE=require postgres:18-alpine psql"

echo ">> Restaurando $KEY em restore_test"
aws s3 cp "s3://$BUCKET/postgres/$KEY" /tmp/restore.sql.gz
$PSQL "$DATABASE_URL" -c "DROP DATABASE IF EXISTS restore_test;" -c "CREATE DATABASE restore_test;"
gunzip -c /tmp/restore.sql.gz | $PSQL "$TEST_URL" -v ON_ERROR_STOP=1 -q
rm -f /tmp/restore.sql.gz

echo ">> Comparando"
echo -n "Banco principal: "; $PSQL "$DATABASE_URL" -tAc "SELECT count(*) FROM tasks;"
echo -n "Backup restaurado: "; $PSQL "$TEST_URL" -tAc "SELECT count(*) FROM tasks;"
