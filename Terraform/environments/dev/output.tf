output "instance_public_ip" {
  description = "Public IP from the main module"
  # אנחנו מושכים את הערך מהמודול שקראת לו dev_infra
  value = module.dev_infra.instance_public_ip
}