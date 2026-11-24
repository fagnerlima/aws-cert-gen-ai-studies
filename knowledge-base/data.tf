# Identidade de quem roda o Tofu: usada para descobrir a conta e para dar a
# esse principal acesso ao índice na política de dados do AOSS, sem fixar ID
# de conta nem nome de usuário no código.
data "aws_caller_identity" "current" {}

# Com role assumida ou SSO, o ARN da chamada é de uma sessão do STS, que o AOSS
# não aceita como principal; o issuer_arn traz o ARN da role (ou do usuário
# IAM, quando não há sessão). Requer iam:GetRole para roles.
data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  bucket_arn          = "arn:${local.partition}:s3:::${var.bucket_name}"
  embedding_model_arn = "arn:${local.partition}:bedrock:${var.region}::foundation-model/${var.embedding_model_id}"

  # Nomes do índice e dos campos que o Bedrock usa no OpenSearch; iguais aos
  # que o console cria por padrão.
  vector_index_name = "bedrock-knowledge-base-default-index"
  vector_field      = "bedrock-knowledge-base-default-vector"
  text_field        = "AMAZON_BEDROCK_TEXT"
  metadata_field    = "AMAZON_BEDROCK_METADATA"
}
