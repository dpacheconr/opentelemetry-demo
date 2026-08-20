variable "region" {
  description = "AWS region to provision the EC2 host in"
  type        = string
  default     = "eu-west-2"
}

variable "instance_type" {
  description = "EC2 instance type; sized for a single-node minikube cluster running the demo (~7GiB of memory limits)"
  type        = string
  default     = "m5.xlarge"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB (container images + minikube state)"
  type        = number
  default     = 60
}

variable "allowed_cidr" {
  description = "CIDR block allowed to reach SSH (22) and the frontend-proxy port (8080) on the instance"
  type        = string
}

variable "public_key_path" {
  description = "Path to an existing SSH public key file to authorize on the instance"
  type        = string
}

variable "name_prefix" {
  description = "Prefix used to name the created AWS resources"
  type        = string
  default     = "otel-demo-minikube"
}
