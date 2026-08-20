output "public_ip" {
  description = "Public IP address of the EC2 host"
  value       = aws_instance.demo_host.public_ip
}

output "public_dns" {
  description = "Public DNS name of the EC2 host"
  value       = aws_instance.demo_host.public_dns
}

output "ssh_command" {
  description = "Command to SSH into the EC2 host"
  value       = "ssh ubuntu@${aws_instance.demo_host.public_ip}"
}

output "frontend_url" {
  description = "URL for the demo storefront once frontend-proxy is port-forwarded on the host"
  value       = "http://${aws_instance.demo_host.public_ip}:8080"
}
