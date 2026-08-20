# EC2 Minikube Demo Host Module

This Terraform module provisions a single EC2 instance running a single-node
[minikube](https://minikube.sigs.k8s.io/) cluster, as an alternative to EKS or
plain docker-compose for running the OpenTelemetry Demo.

## Purpose

Use this module to:

1. Provision an EC2 instance sized for the demo's Kubernetes/Helm deploy path
2. Install Docker, `kubectl`, `helm`, and `minikube` on first boot via `user_data`
3. Start a single-node minikube cluster automatically
4. Tear everything down with a single `terraform destroy`

The New Relic license key and the actual demo deployment (`newrelic/scripts/install-k8s.sh`)
are handled separately, over SSH, once the instance is up — they are not part
of this module so no secrets end up in `user_data` or Terraform state.

## Prerequisites

- Terraform >= 1.4
- AWS account and credentials configured (e.g. `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`, or an AWS CLI profile)
- An existing local SSH key pair (`public_key_path` points at the `.pub` file)

## Usage

```bash
cd newrelic/terraform/ec2_demo_host

terraform init
terraform apply \
  -var="allowed_cidr=<your-ip>/32" \
  -var="public_key_path=~/.ssh/id_ed25519.pub"
```

Once applied, wait for cloud-init to finish, then deploy the demo:

```bash
ssh ubuntu@$(terraform output -raw public_ip) 'cloud-init status --wait'

# Copy the scripts needed to deploy the demo
scp -r ../../scripts ../../k8s ubuntu@$(terraform output -raw public_ip):~/newrelic/

ssh ubuntu@$(terraform output -raw public_ip)
cd newrelic/scripts
./install-k8s.sh   # prompts for NEW_RELIC_LICENSE_KEY and region interactively
kubectl port-forward -n opentelemetry-demo svc/frontend-proxy 8080:8080 --address 0.0.0.0 &
```

Browse to `terraform output frontend_url` (e.g. `http://<public-ip>:8080`).

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | AWS region to provision the EC2 host in | `string` | `"us-east-1"` | no |
| instance_type | EC2 instance type | `string` | `"m5.xlarge"` | no |
| root_volume_size | Root EBS volume size in GiB | `number` | `60` | no |
| allowed_cidr | CIDR allowed to reach SSH (22) and frontend-proxy (8080) | `string` | n/a | yes |
| public_key_path | Path to an existing SSH public key file | `string` | n/a | yes |
| name_prefix | Prefix for created AWS resource names | `string` | `"otel-demo-minikube"` | no |

## Outputs

| Name | Description |
|------|-------------|
| public_ip | Public IP address of the EC2 host |
| public_dns | Public DNS name of the EC2 host |
| ssh_command | Ready-to-use SSH command |
| frontend_url | URL for the demo storefront once frontend-proxy is port-forwarded |

## Sizing

`m5.xlarge` (4 vCPU / 16GiB) covers the ~7GiB of memory **limits** across demo
services (see `kubernetes/opentelemetry-demo.yaml`) plus the New Relic collector,
OS, and minikube control-plane overhead, since this is a single-node cluster
with no per-node kube-system replication.

## Teardown

```bash
terraform destroy
```

Removes the EC2 instance, security group, and key pair. Nothing else in the
AWS account is touched.
