# Role que o Bedrock assume para ler o bucket, gerar embeddings e gravar no
# índice. Substitui a role criada pelo console, com mínimo privilégio.

data "aws_iam_policy_document" "kb_trust" {
  statement {
    sid     = "AllowBedrockKnowledgeBase"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    # Evita o problema do "confused deputy": só Knowledge Bases desta conta e
    # região podem assumir a role.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:bedrock:${var.region}:${local.account_id}:knowledge-base/*"]
    }
  }
}

resource "aws_iam_role" "kb" {
  name               = "${var.knowledge_base_name}-kb-role"
  description        = "Role da Knowledge Base ${var.knowledge_base_name} do Bedrock (gerenciada pelo OpenTofu)."
  assume_role_policy = data.aws_iam_policy_document.kb_trust.json
}

data "aws_iam_policy_document" "kb_permissions" {
  statement {
    sid       = "InvokeEmbeddingModel"
    actions   = ["bedrock:InvokeModel"]
    resources = [local.embedding_model_arn]
  }

  statement {
    sid       = "ListBookBucket"
    actions   = ["s3:ListBucket"]
    resources = [local.bucket_arn]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "ReadBookObjects"
    actions   = ["s3:GetObject"]
    resources = ["${local.bucket_arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "AccessVectorCollection"
    actions   = ["aoss:APIAccessAll"]
    resources = [aws_opensearchserverless_collection.kb.arn]
  }
}

resource "aws_iam_role_policy" "kb" {
  name   = "${var.knowledge_base_name}-kb-permissions"
  role   = aws_iam_role.kb.id
  policy = data.aws_iam_policy_document.kb_permissions.json
}

# O IAM é eventualmente consistente: o Bedrock valida a role ao criar a
# Knowledge Base e pode recusá-la se a política ainda não propagou.
resource "time_sleep" "wait_iam_propagation" {
  create_duration = "20s"

  depends_on = [aws_iam_role_policy.kb]
}
