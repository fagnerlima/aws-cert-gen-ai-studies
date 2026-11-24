# Usa as credenciais padrão do AWS CLI (perfil default ou variáveis de ambiente).
provider "aws" {
  region = var.region
}

# Fala direto com a coleção do OpenSearch Serverless para criar o índice
# vetorial. As requisições são assinadas com SigV4 usando as mesmas
# credenciais padrão; o healthcheck fica desligado porque o AOSS não expõe os
# endpoints de cluster que ele consulta.
provider "opensearch" {
  url                   = aws_opensearchserverless_collection.kb.collection_endpoint
  aws_region            = var.region
  aws_signature_service = "aoss"
  healthcheck           = false
}
