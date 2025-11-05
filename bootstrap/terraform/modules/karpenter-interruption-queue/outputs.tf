output "queue_arn" {
  description = "ARN of the Karpenter interruption queue"
  value       = aws_sqs_queue.karpenter_interruption.arn
}

output "queue_url" {
  description = "URL of the Karpenter interruption queue"
  value       = aws_sqs_queue.karpenter_interruption.url
}

output "queue_name" {
  description = "Name of the Karpenter interruption queue"
  value       = aws_sqs_queue.karpenter_interruption.name
}
