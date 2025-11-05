# ============================================================================
# Karpenter Interruption Queue - SQS and EventBridge
# ============================================================================

# SQS Queue for spot interruption notifications
resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = var.queue_name
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = {
    Service = "karpenter"
    Purpose = "spot-interruption"
  }
}

# SQS Queue Policy to allow EventBridge to send messages
data "aws_iam_policy_document" "karpenter_interruption_queue_policy" {
  statement {
    sid    = "AllowEventBridgeToSendMessage"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }

    actions = [
      "sqs:SendMessage"
    ]

    resources = [
      aws_sqs_queue.karpenter_interruption.arn
    ]
  }
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id
  policy    = data.aws_iam_policy_document.karpenter_interruption_queue_policy.json
}

# EventBridge Rule for EC2 Spot Instance Interruption Warning
resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "${var.cluster_name}-spot-interruption"
  description = "Capture EC2 spot instance interruption warnings"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })

  tags = {
    Service = "karpenter"
    Purpose = "spot-interruption"
  }
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule      = aws_cloudwatch_event_rule.spot_interruption.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

# EventBridge Rule for EC2 Instance Rebalance Recommendation
resource "aws_cloudwatch_event_rule" "rebalance_recommendation" {
  name        = "${var.cluster_name}-rebalance-recommendation"
  description = "Capture EC2 instance rebalance recommendations"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })

  tags = {
    Service = "karpenter"
    Purpose = "rebalance-recommendation"
  }
}

resource "aws_cloudwatch_event_target" "rebalance_recommendation" {
  rule      = aws_cloudwatch_event_rule.rebalance_recommendation.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

# EventBridge Rule for EC2 Instance State-change Notification
resource "aws_cloudwatch_event_rule" "instance_state_change" {
  name        = "${var.cluster_name}-instance-state-change"
  description = "Capture EC2 instance state change notifications"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })

  tags = {
    Service = "karpenter"
    Purpose = "instance-state-change"
  }
}

resource "aws_cloudwatch_event_target" "instance_state_change" {
  rule      = aws_cloudwatch_event_rule.instance_state_change.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

# EventBridge Rule for AWS Health Events
resource "aws_cloudwatch_event_rule" "health_event" {
  name        = "${var.cluster_name}-health-event"
  description = "Capture AWS Health events affecting EC2 instances"

  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
  })

  tags = {
    Service = "karpenter"
    Purpose = "health-event"
  }
}

resource "aws_cloudwatch_event_target" "health_event" {
  rule      = aws_cloudwatch_event_rule.health_event.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}
