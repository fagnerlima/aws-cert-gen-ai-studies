output "bucket_name" {
  description = "Nome do bucket com o material da Knowledge Base."
  value       = aws_s3_bucket.book.bucket
}

output "bucket_arn" {
  description = "ARN do bucket com o material da Knowledge Base."
  value       = aws_s3_bucket.book.arn
}
