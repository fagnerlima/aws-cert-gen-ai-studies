# Recursos que ficam sempre na conta (custo quase zero) e não são destruídos
# pelo scripts/down.sh. O bucket foi criado pelo console; os blocos import
# trazem a configuração atual para o state na primeira execução de apply.
# Cada recurso espelha exatamente a configuração atual, para o plan não
# mostrar mudanças além dos imports.

import {
  to = aws_s3_bucket.book
  id = var.bucket_name
}

import {
  to = aws_s3_bucket_public_access_block.book
  id = var.bucket_name
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.book
  id = var.bucket_name
}

resource "aws_s3_bucket" "book" {
  bucket = var.bucket_name

  # O bucket guarda o material do curso; nunca deve ser apagado pelo Tofu.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "book" {
  bucket = aws_s3_bucket.book.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "book" {
  bucket = aws_s3_bucket.book.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }

    bucket_key_enabled = true

    # Padrão atual da AWS para buckets novos: bloqueia uploads com SSE-C.
    blocked_encryption_types = ["SSE-C"]
  }
}
