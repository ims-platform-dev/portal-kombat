output "tagged_subnet_ids" {
  description = "List of subnet IDs that were tagged"
  value       = var.subnet_ids
}

output "tagged_security_group_ids" {
  description = "List of security group IDs that were tagged"
  value       = var.security_group_ids
}
