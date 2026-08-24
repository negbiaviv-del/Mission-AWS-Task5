terraform {
  backend "s3" {
    bucket       = "aviv-mission-aws-bucket-1997"
    key          = "environments/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}