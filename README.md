# elo-lab

Versão mínima da arquitetura do CRM para treinar a infraestrutura na AWS:
API (Express + SSE) → fila BullMQ no Redis → worker → Postgres, com logs no MongoDB.

O passo a passo completo está no documento **Laboratório AWS — Roteiro de 2 Semanas**.

## Estrutura

| Caminho | O que é |
| --- | --- |
| `api/` | API: cria tarefas, lista resultados, transmite progresso por SSE, `/health` |
| `worker/` | Consome a fila, simula processamento, grava no Postgres |
| `docker-compose.yml` | Ambiente local completo (todos os bancos em containers) |
| `docker-compose.prod.yml` | Ambiente na AWS: RDS, Atlas e segredos do Secrets Manager |
| `scripts/ec2-setup.sh` | Preparação da EC2 (user data) |
| `scripts/deploy.sh` | Atualiza a aplicação na EC2 |
| `scripts/backup-postgres.sh` | Dump do Postgres para o S3 |
| `scripts/restore-test.sh` | Restaura o último backup num banco separado e compara |
| `scripts/install-backup-timer.sh` | Agenda o backup diário |
| `scripts/create-alarms.sh` | Cria os alertas do CloudWatch |
| `infra/*.json` | Políticas de acesso (IAM) da EC2 e do usuário de deploy do GitHub Actions |
| `.github/workflows/deploy.yml` | CI/CD: verifica, gera as imagens, envia ao ECR e faz o deploy |

## Rodar

O laboratório foi pensado para o **GitHub Codespaces**: a pasta `.devcontainer` já traz Docker, Node 22 e AWS CLI.

```bash
docker compose up --build
# abra a porta 3000 na aba Ports
```

Para entrar na AWS de dentro do Codespace: `aws login --remote --profile lab --region us-east-2`.

## Observações para o ambiente real

- O laboratório aceita o certificado do RDS sem validar (`PGSSL=true`). No ambiente de cliente, valide com o bundle de CA da AWS.
- O repositório do laboratório pode ser público porque não tem nenhum segredo. No projeto real, o repositório é privado e a EC2 usa uma deploy key só de leitura.
- Troque `SUA_CONTA` e `SEU_BUCKET` nos arquivos de `infra/`, e `SEU_USUARIO` em `scripts/ec2-setup.sh`.
- A região é `us-east-2` (Ohio), a que a AWS define para contas do Brasil no modelo novo (projetos).
- O modelo novo bloqueia o login do GitHub por OIDC. Por isso o deploy usa a chave de um usuário com permissão mínima. Numa conta no modelo completo (advanced), troque pela role com OIDC.
