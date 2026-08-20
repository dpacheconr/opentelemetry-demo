variable "region" {
  description = "AWS region to provision the EC2 host in"
  type        = string
  default     = "eu-west-2"
}

variable "instance_type" {
  description = "EC2 instance type; sized for a single-node minikube cluster running the demo (~7GiB of memory limits)"
  type        = string
  default     = "t2.xlarge"
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

variable "new_relic_license_key" {
  description = "New Relic license key, stored in SSM Parameter Store (SecureString) and read by the instance at boot"
  type        = string
  sensitive   = true
}

variable "new_relic_region" {
  description = "New Relic region (us, eu, jp)"
  type        = string
  default     = "us"
}

variable "otel_demo_chart_version" {
  description = "Version of the open-telemetry/opentelemetry-demo Helm chart"
  type        = string
  default     = "0.40.10"
}

variable "nr_k8s_chart_version" {
  description = "Version of the newrelic/nr-k8s-otel-collector Helm chart"
  type        = string
  default     = "0.13.0"
}
