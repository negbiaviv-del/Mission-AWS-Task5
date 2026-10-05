# ==============================================================================
# הגדרת ספקים (Providers):
# נעילת גרסאות הפלאגינים של טרפורם מול
# AWS וקוברנטיס
# ==============================================================================
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # הגרסה עודכנה ל-5.51.0 ומעלה כדי לתמוך ב-EKS 1.30
      version = ">= 5.51.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
  }
}

# הגדרת אזור הפעילות הראשי של הפרויקט בענן של אמזון
provider "aws" {
  region = "us-east-1"
}
