terraform {
  backend "s3" {
    bucket       = "aviv-mission-aws-bucket-1997"
    key          = "environments/staging/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}