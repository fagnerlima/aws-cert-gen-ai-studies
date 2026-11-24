terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.74"
    }
    opensearch = {
      source  = "opensearch-project/opensearch"
      version = "~> 2.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }
}
