variable "region" {
  description = "Região AWS da Knowledge Base, da coleção e do modelo de embedding."
  type        = string
  default     = "us-east-1"
}

variable "knowledge_base_name" {
  description = "Nome da Knowledge Base do Bedrock."
  type        = string
  default     = "sundog-rag"
}

variable "data_source_name" {
  description = "Nome do data source S3 da Knowledge Base."
  type        = string
  default     = "franks-book"
}

variable "bucket_name" {
  description = "Bucket S3 (gerenciado em persistent/) com os documentos da Knowledge Base."
  type        = string
  default     = "sundog-franks-book-fl"
}

variable "collection_name" {
  description = "Nome da coleção do OpenSearch Serverless; também é o prefixo das políticas (3 a 32 caracteres, minúsculas, números e hífen, começando por letra)."
  type        = string
  default     = "sundog-rag"

  validation {
    # Os nomes das políticas acrescentam até 7 caracteres ("-access") e
    # também têm limite de 32.
    condition     = can(regex("^[a-z][a-z0-9-]{2,24}$", var.collection_name))
    error_message = "Use de 3 a 25 caracteres: letras minúsculas, números e hífen, começando por letra (o sufixo das políticas precisa caber em 32)."
  }
}

variable "embedding_model_id" {
  description = "ID do modelo de fundação usado para gerar os embeddings."
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "embedding_dimensions" {
  description = "Dimensão dos vetores gerados pelo modelo de embedding."
  type        = number
  default     = 1024
}
