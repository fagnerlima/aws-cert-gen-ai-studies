#!/usr/bin/env bash
# Cria a Knowledge Base (OpenTofu) e sincroniza o data source, esperando a
# ingestão terminar. Uso: scripts/up.sh [argumentos do tofu apply]
# Exemplo: scripts/up.sh -auto-approve
#
# Variáveis de ambiente opcionais (inteiros positivos, em segundos):
#   INGESTION_TIMEOUT_SECONDS  tempo máximo de espera da ingestão (padrão 900)
#   INGESTION_POLL_SECONDS     intervalo entre consultas (padrão 15)
set -euo pipefail
export AWS_PAGER=""

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kb_dir="$script_dir/../knowledge-base"
timeout_seconds="${INGESTION_TIMEOUT_SECONDS:-900}"
poll_seconds="${INGESTION_POLL_SECONDS:-15}"

require_positive_integer() {
  local name="$1" value="$2"

  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERRO: $name deve ser um inteiro positivo (recebido: '$value')." >&2
    exit 2
  fi
}

require_positive_integer INGESTION_TIMEOUT_SECONDS "$timeout_seconds"
require_positive_integer INGESTION_POLL_SECONDS "$poll_seconds"

warn_on_failure() {
  local status=$?

  if ((status != 0)); then
    echo >&2
    echo "AVISO: o up.sh falhou (código $status). Se a coleção do OpenSearch Serverless" >&2
    echo "foi criada, ela já está cobrando por hora. Corrija e rode o up.sh de novo," >&2
    echo "ou rode scripts/down.sh para destruir o que foi criado." >&2
  fi
}

trap warn_on_failure EXIT

if [[ ! -d "$kb_dir/.terraform" ]]; then
  tofu -chdir="$kb_dir" init -input=false
fi

tofu -chdir="$kb_dir" apply "$@"

knowledge_base_id="$(tofu -chdir="$kb_dir" output -raw knowledge_base_id)"
data_source_id="$(tofu -chdir="$kb_dir" output -raw data_source_id)"
region="$(tofu -chdir="$kb_dir" output -raw region)"

ingestion_job() {
  aws bedrock-agent get-ingestion-job \
    --region "$region" \
    --knowledge-base-id "$knowledge_base_id" \
    --data-source-id "$data_source_id" \
    --ingestion-job-id "$job_id" \
    "$@"
}

# Reaproveita um job em andamento (por exemplo, de uma execução interrompida)
# em vez de iniciar outro, que seria recusado pelo Bedrock.
job_id="$(aws bedrock-agent list-ingestion-jobs \
  --region "$region" \
  --knowledge-base-id "$knowledge_base_id" \
  --data-source-id "$data_source_id" \
  --query "ingestionJobSummaries[?status=='STARTING' || status=='IN_PROGRESS' || status=='STOPPING'] | [0].ingestionJobId" \
  --output text)"

if [[ -n "$job_id" && "$job_id" != "None" ]]; then
  echo "Já existe uma ingestão em andamento ($job_id); acompanhando esse job."
else
  echo "Iniciando a ingestão (KB $knowledge_base_id, data source $data_source_id)..."
  job_id="$(aws bedrock-agent start-ingestion-job \
    --region "$region" \
    --knowledge-base-id "$knowledge_base_id" \
    --data-source-id "$data_source_id" \
    --query 'ingestionJob.ingestionJobId' \
    --output text)"
fi

deadline=$((SECONDS + timeout_seconds))

while true; do
  status="$(ingestion_job --query 'ingestionJob.status' --output text)"
  echo "Ingestão $job_id: $status"

  case "$status" in
    COMPLETE)
      ingestion_job --query 'ingestionJob.statistics' --output table
      failed_documents="$(ingestion_job --query 'ingestionJob.statistics.numberOfDocumentsFailed' --output text)"

      if [[ "$failed_documents" != "0" && "$failed_documents" != "None" ]]; then
        echo "ERRO: a ingestão terminou, mas $failed_documents documento(s) falharam. Motivos:" >&2
        ingestion_job --query 'ingestionJob.failureReasons' --output text >&2
        exit 1
      fi

      echo "Knowledge Base pronta: $knowledge_base_id (região $region)."
      exit 0
      ;;
    FAILED | STOPPED)
      echo "ERRO: a ingestão terminou com status $status. Motivos:" >&2
      ingestion_job --query 'ingestionJob.failureReasons' --output text >&2
      exit 1
      ;;
  esac

  if ((SECONDS >= deadline)); then
    echo "ERRO: a ingestão $job_id não terminou em ${timeout_seconds}s (último status: $status)." >&2
    echo "Ela continua rodando na AWS: acompanhe no console do Bedrock ou rode o up.sh" >&2
    echo "de novo, que acompanha o mesmo job (aumente INGESTION_TIMEOUT_SECONDS se preciso)." >&2
    exit 1
  fi

  sleep "$poll_seconds"
done
