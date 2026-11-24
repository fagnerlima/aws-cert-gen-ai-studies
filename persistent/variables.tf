variable "region" {
  description = "Região AWS onde o bucket existe."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Nome do bucket S3 já existente com o livro usado como fonte da Knowledge Base."
  type        = string
  default     = "sundog-franks-book-fl"
}
