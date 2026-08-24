output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

# --- Subnets ---

output "public_subnet_1_id" {
  description = "ID of the first public subnet (for Nginx)"
  value       = aws_subnet.public_1.id
}

output "public_subnet_2_id" {
  description = "ID of the second public subnet"
  value       = aws_subnet.public_2.id
}

output "private_subnet_1_id" {
  description = "ID of the first private subnet (for RDS)"
  value       = aws_subnet.private_1.id
}

output "private_subnet_2_id" {
  description = "ID of the second private subnet"
  value       = aws_subnet.private_2.id
}

# --- DB Specific ---

output "rds_subnet_group_id" {
  description = "The ID of the RDS subnet group"
  value       = aws_db_subnet_group.rds_subnet_group.id
}

# --- Security Groups ---

output "nginx_sg_id" {
  description = "The ID of the Nginx security group"
  value       = aws_security_group.nginx_sg.id
}

output "backend_sg_id" {
  description = "The ID of the Backend security group"
  value       = aws_security_group.backend_sg.id
}

output "db_sg_id" {
  description = "The ID of the Database security group"
  value       = aws_security_group.db_sg.id
}