terraform {
  backend "s3" {
    bucket       = "aviv-mission-aws-bucket-app-dev-1997"
    key          = "environments/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}