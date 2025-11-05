output "eks_cluster_id" {
  description = "Kubernetes Cluster Name"
  value       = module.eks.cluster_id
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --alias ${local.name} --region ${local.region}"
}

output "cluster_autoscaler_role_arn" {
  description = "ARN of the Cluster Autoscaler IAM role"
  value       = module.cluster_autoscaler_irsa.iam_role_arn
}

output "cluster_autoscaler_role_name" {
  description = "Name of the Cluster Autoscaler IAM role"
  value       = module.cluster_autoscaler_irsa.iam_role_name
}

