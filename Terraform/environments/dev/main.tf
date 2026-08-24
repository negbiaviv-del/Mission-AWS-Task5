module "dev_infra" {
  source = "../../"

  aws_region         = var.avd_aws_region
  ami_id             = var.avd_aws_ec2_ami_id
  instance_type      = var.avd_aws_ec2_instance_type
  key_name           = var.avd_aws_key_name
  vpc_cidr           = var.avd_aws_vpc_cidr
  subnet_cidr        = var.avd_aws_public_subnet_cidr
  subnet2_cidr       = var.avd_aws_public_subnet_2_cidr
  bucket_name        = var.avd_aws_s3_bucket_name
  db_name            = var.avd_aws_db_name
  db_user            = var.avd_aws_db_user
  db_password        = var.avd_aws_db_password
  sns_topic_name     = var.avd_aws_sns_topic_name
  secret_name        = var.avd_aws_secret_name
  secret_description = "Secret for dev environment"

  iam_role  = "aviv-mission-iam-role"
  subnet_id = "temp-id"
}