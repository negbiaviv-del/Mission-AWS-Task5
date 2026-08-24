output "instance_profile_name" {
  description = "The name of the IAM instance profile"
  value       = aws_iam_instance_profile.ec2_profile.name
}

output "iam_instance_profile_name" {
  value = aws_iam_instance_profile.ec2_profile.name
}