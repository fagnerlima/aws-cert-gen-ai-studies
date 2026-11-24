#!/usr/bin/env bash
# Destrói a Knowledge Base, a coleção do OpenSearch Serverless e a role
# (o bucket em persistent/ não é afetado) e confere se sobrou alguma coleção
# cobrando na região, mesmo que o destroy falhe.
# Uso: scripts/down.sh [argumentos do tofu destroy]
# Exemplo: scripts/down.sh -auto-approve
set -euo pipefail
export AWS_PAGER=""

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kb_dir="$script_dir/../knowledge-base"
default_region="us-east-1"

if [[ ! -d "$kb_dir/.terraform" ]]; then
  tofu -chdir="$kb_dir" init -input=false
fi

# Lê a região antes do destroy, porque depois o state fica sem outputs.
region="$(tofu -chdir="$kb_dir" output -raw region 2>/dev/null || echo "$default_region")"

destroy_status=0
tofu -chdir="$kb_dir" destroy "$@" || destroy_status=$?

if ((destroy_status != 0)); then
  echo "ERRO: o tofu destroy falhou ou foi cancelado (código $destroy_status). Veja \"Se o destroy travar\" no README." >&2
fi

# Conta qualquer coleção da região, não só a desta KB: todas cobram por hora.
remaining="$(aws opensearchserverless list-collections \
  --region "$region" \
  --query 'collectionSummaries[].[name,status]' \
  --output text)"

if [[ -n "${remaining//[[:space:]]/}" ]]; then
  echo "AVISO: ainda existem coleções do OpenSearch Serverless em $region (continuam cobrando por hora):" >&2
  echo "$remaining" >&2
  exit 1
fi

echo "Nenhuma coleção do OpenSearch Serverless em $region."
exit "$destroy_status"
