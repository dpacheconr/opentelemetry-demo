#!/bin/bash
set -euo pipefail

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
