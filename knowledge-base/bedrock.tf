resource "aws_bedrockagent_knowledge_base" "kb" {
  name     = var.knowledge_base_name
  role_arn = aws_iam_role.kb.arn

  knowledge_base_configuration {
    type = "VECTOR"

    vector_knowledge_base_configuration {
      embedding_model_arn = local.embedding_model_arn

      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          dimensions          = var.embedding_dimensions
          embedding_data_type = "FLOAT32"
        }
      }
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"

    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.kb.arn
      vector_index_name = opensearch_index.kb.name

      field_mapping {
        vector_field   = local.vector_field
        text_field     = local.text_field
        metadata_field = local.metadata_field
      }
    }
  }

  # A sincronização do Bedrock é incremental: se o índice for recriado, só uma
  # KB nova (e com ela um data source novo) reprocessa todos os documentos.
  lifecycle {
    replace_triggered_by = [terraform_data.index_mappings]
  }

  # O Bedrock valida a role e o índice na criação: espera a política IAM
  # propagar e o índice ficar disponível.
  depends_on = [
    time_sleep.wait_iam_propagation,
    time_sleep.wait_index,
  ]
}

resource "aws_bedrockagent_data_source" "book" {
  name                 = var.data_source_name
  knowledge_base_id    = aws_bedrockagent_knowledge_base.kb.id
  data_deletion_policy = "DELETE"

  # Sem vector_ingestion_configuration: usa o chunking padrão do Bedrock,
  # como a configuração feita no console.
  data_source_configuration {
    type = "S3"

    s3_configuration {
      bucket_arn = local.bucket_arn
    }
  }
}
