#!/bin/bash
# Cria os alertas do CloudWatch (Sessão 7). Rode no SEU computador.
# Uso: bash scripts/create-alarms.sh <id-da-ec2> <id-do-rds> <seu-email>
set -euo pipefail
INSTANCE_ID="$1"; DB_ID="$2"; EMAIL="$3"
export AWS_PROFILE="${AWS_PROFILE:-lab}" AWS_REGION="${AWS_REGION:-us-east-2}"

TOPIC=$(aws sns create-topic --name elo-lab-alertas --query TopicArn --output text)
aws sns subscribe --topic-arn "$TOPIC" --protocol email --notification-endpoint "$EMAIL" >/dev/null
echo "Confirme a inscrição no e-mail que a AWS enviou para $EMAIL"

alarm() { # nome, namespace, métrica, dimensão, estatística, operador, limite, períodos
  aws cloudwatch put-metric-alarm --alarm-name "$1" --namespace "$2" --metric-name "$3" \
    --dimensions "$4" --statistic "$5" --period 300 --evaluation-periods "$8" \
    --comparison-operator "$6" --threshold "$7" --treat-missing-data notBreaching \
    --alarm-actions "$TOPIC" --ok-actions "$TOPIC"
  echo "Alerta criado: $1"
}
alarm elo-lab-ec2-cpu-alta      AWS/EC2 CPUUtilization     "Name=InstanceId,Value=$INSTANCE_ID" Average GreaterThanThreshold 80 2
alarm elo-lab-ec2-check-falhou  AWS/EC2 StatusCheckFailed  "Name=InstanceId,Value=$INSTANCE_ID" Maximum GreaterThanOrEqualToThreshold 1 1
alarm elo-lab-rds-cpu-alta      AWS/RDS CPUUtilization     "Name=DBInstanceIdentifier,Value=$DB_ID" Average GreaterThanThreshold 80 2
alarm elo-lab-rds-pouco-disco   AWS/RDS FreeStorageSpace   "Name=DBInstanceIdentifier,Value=$DB_ID" Minimum LessThanThreshold 2000000000 1

# Erros da aplicação: conta as linhas "[error]" nos logs do worker
aws logs put-metric-filter --log-group-name /elo-lab/worker --filter-name erros-worker \
  --filter-pattern '"[error]"' \
  --metric-transformations metricName=ErrosWorker,metricNamespace=EloLab,metricValue=1,defaultValue=0
aws cloudwatch put-metric-alarm --alarm-name elo-lab-worker-erros --namespace EloLab --metric-name ErrosWorker \
  --statistic Sum --period 300 --evaluation-periods 1 --comparison-operator GreaterThanOrEqualToThreshold \
  --threshold 3 --treat-missing-data notBreaching --alarm-actions "$TOPIC"
echo "Alerta criado: elo-lab-worker-erros"
