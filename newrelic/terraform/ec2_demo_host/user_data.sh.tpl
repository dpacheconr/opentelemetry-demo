#!/bin/bash
set -euo pipefail

# AWS CLI (to read the license key from SSM Parameter Store)
apt-get update -y
apt-get install -y unzip
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install

# Docker Engine (minikube's docker driver requires it)
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu

# kubectl
curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

# Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# minikube
curl -fsSL -o /usr/local/bin/minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
chmod +x /usr/local/bin/minikube

# Start a single-node cluster as the ubuntu user (minikube refuses to run as root with the docker driver)
sudo -u ubuntu -i minikube start --driver=docker --cpus=4 --memory=14g --kubernetes-version=stable

mkdir -p /opt/otel-demo
cat >/opt/otel-demo/opentelemetry-demo-values.yaml <<'VALUES_EOF'
${otel_demo_values}
VALUES_EOF

cat >/opt/otel-demo/nr-k8s-otel-collector-values.yaml <<'VALUES_EOF'
${nr_k8s_otel_collector_values}
VALUES_EOF

NEW_RELIC_LICENSE_KEY=$(aws ssm get-parameter \
  --name "${ssm_license_key_param}" \
  --with-decryption \
  --region "${aws_region}" \
  --query 'Parameter.Value' --output text)

export KUBECONFIG=/home/ubuntu/.kube/config

kubectl create ns opentelemetry-demo
kubectl create secret generic newrelic-license-key \
  --from-literal=license-key="$NEW_RELIC_LICENSE_KEY" \
  -n opentelemetry-demo

helm repo add newrelic https://helm-charts.newrelic.com
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

helm upgrade nr-k8s-otel-collector newrelic/nr-k8s-otel-collector \
  --version "${nr_k8s_chart_version}" \
  -f /opt/otel-demo/nr-k8s-otel-collector-values.yaml \
  --set "global.region=${new_relic_region}" \
  -n opentelemetry-demo --install

helm upgrade otel-demo open-telemetry/opentelemetry-demo \
  --version "${otel_demo_chart_version}" \
  -f /opt/otel-demo/opentelemetry-demo-values.yaml \
  -n opentelemetry-demo --install
