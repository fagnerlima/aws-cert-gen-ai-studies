# Coleção vetorial do OpenSearch Serverless (AOSS). É o recurso que cobra por
# hora mesmo sem uso; por isso este diretório é criado e destruído a cada
# sessão de estudo (scripts/up.sh e scripts/down.sh).

locals {
  collection_resource = "collection/${var.collection_name}"
  index_resource      = "index/${var.collection_name}/*"
}

resource "aws_opensearchserverless_security_policy" "encryption" {
  name        = "${var.collection_name}-enc"
  type        = "encryption"
  description = "Criptografia da coleção ${var.collection_name} com chave da AWS."

  policy = jsonencode({
    Rules = [
      {
        ResourceType = "collection"
        Resource     = [local.collection_resource]
      }
    ]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  name        = "${var.collection_name}-net"
  type        = "network"
  description = "Acesso público (autenticado por IAM) ao endpoint da coleção ${var.collection_name}."

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource     = [local.collection_resource]
        }
      ]
      AllowFromPublic = true
    }
  ])
}

resource "aws_opensearchserverless_access_policy" "data" {
  name        = "${var.collection_name}-access"
  type        = "data"
  description = "Acesso a dados da coleção ${var.collection_name} para a role da KB e para quem roda o Tofu."

  policy = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource     = [local.collection_resource]
          Permission = [
            "aoss:DescribeCollectionItems",
            "aoss:CreateCollectionItems",
            "aoss:UpdateCollectionItems",
          ]
        },
        {
          ResourceType = "index"
          Resource     = [local.index_resource]
          Permission = [
            "aoss:CreateIndex",
            "aoss:DescribeIndex",
            "aoss:UpdateIndex",
            # Necessária para o destroy apagar o índice antes da coleção.
            "aoss:DeleteIndex",
            "aoss:ReadDocument",
            "aoss:WriteDocument",
          ]
        }
      ]
      Principal = [
        aws_iam_role.kb.arn,
        data.aws_iam_session_context.current.issuer_arn,
      ]
    }
  ])
}

resource "aws_opensearchserverless_collection" "kb" {
  name        = var.collection_name
  type        = "VECTORSEARCH"
  description = "Armazenamento vetorial da Knowledge Base ${var.knowledge_base_name}."

  # Igual à coleção criada pelo console para a KB. O padrão da API é ENABLED,
  # que dobra as OCUs mínimas (e o custo) para ter réplicas em outra AZ.
  standby_replicas = "DISABLED"

  # A coleção só pode ser criada depois que existe uma política de
  # criptografia que a cubra; a de rede evita uma janela sem acesso.
  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
  ]
}

# A política de acesso a dados demora para valer; sem esta espera a criação do
# índice costuma falhar com 403.
resource "time_sleep" "wait_data_access_policy" {
  create_duration = "60s"

  depends_on = [
    aws_opensearchserverless_access_policy.data,
    aws_opensearchserverless_collection.kb,
  ]
}

locals {
  index_mappings = jsonencode({
    properties = {
      (local.vector_field) = {
        type      = "knn_vector"
        dimension = var.embedding_dimensions
        method = {
          name       = "hnsw"
          engine     = "faiss"
          space_type = "l2"
          parameters = {
            m               = 16
            ef_construction = 512
          }
        }
      }
      (local.text_field) = {
        type = "text"
      }
      (local.metadata_field) = {
        type  = "text"
        index = false
      }
    }
  })
}

# Guarda o mapping desejado: quando ele muda no código, o índice é recriado
# (ver replace_triggered_by abaixo), mesmo com ignore_changes em mappings.
resource "terraform_data" "index_mappings" {
  input = local.index_mappings
}

resource "opensearch_index" "kb" {
  name                           = local.vector_index_name
  index_knn                      = true
  index_knn_algo_param_ef_search = "512"
  force_destroy                  = true
  mappings                       = local.index_mappings

  # O AOSS devolve o mapping normalizado (com campos que o Bedrock acrescenta
  # na ingestão), o que faria o provider propor recriar o índice e apagar os
  # vetores a cada apply. Mudanças no mapping do código recriam o índice pelo
  # terraform_data, e a KB e o data source junto (ver bedrock.tf), para que a
  # próxima ingestão reprocesse todos os documentos.
  lifecycle {
    ignore_changes       = [mappings]
    replace_triggered_by = [terraform_data.index_mappings]
  }

  depends_on = [time_sleep.wait_data_access_policy]
}

# O índice recém-criado demora alguns segundos para ficar disponível; sem esta
# espera o Bedrock pode recusar a criação da KB por não encontrá-lo.
resource "time_sleep" "wait_index" {
  create_duration = "30s"

  # Repete a espera quando o índice é recriado.
  lifecycle {
    replace_triggered_by = [opensearch_index.kb]
  }

  depends_on = [opensearch_index.kb]
}
