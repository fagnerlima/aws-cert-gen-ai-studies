output "knowledge_base_id" {
  description = "ID da Knowledge Base (usado pelo scripts/up.sh e no console)."
  value       = aws_bedrockagent_knowledge_base.kb.id
}

output "data_source_id" {
  description = "ID do data source S3 (usado para iniciar a ingestão)."
  value       = aws_bedrockagent_data_source.book.data_source_id
}

output "region" {
  description = "Região onde a Knowledge Base foi criada."
  value       = var.region
}

output "collection_endpoint" {
  description = "Endpoint da coleção do OpenSearch Serverless."
  value       = aws_opensearchserverless_collection.kb.collection_endpoint
}
