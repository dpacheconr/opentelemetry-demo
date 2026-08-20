output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group managing the demo host"
  value       = aws_autoscaling_group.demo_host.name
}

output "find_current_ip_command" {
  description = "AWS CLI command to look up the current instance's public IP (changes on every scheduled restart)"
  value       = "aws ec2 describe-instances --region ${var.region} --filters Name=tag:Name,Values=${var.name_prefix}-host Name=instance-state-name,Values=running --query 'Reservations[0].Instances[0].PublicIpAddress' --output text"
}

output "schedule" {
  description = "When the instance is running"
  value       = "Runs weekdays 06:00-20:00 UTC (Mon-Fri), stopped (0 instances) on weekends"
}
