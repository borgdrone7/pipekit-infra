# Quick Run — Commands Only

Full explanation of each step is in `running.md`. This file is commands only.

---

## Prerequisites

```bash
# Docker (Ubuntu)
sudo apt-get install -y docker.io && sudo usermod -aG docker $USER && newgrp docker

# k3d
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# OpenTofu (Ubuntu)
sudo snap install opentofu --classic

# kubectl (Ubuntu)
sudo snap install kubectl --classic
```

---

## Run

```bash
# 1. Clone
git clone https://github.com/borgdrone7/pipekit-infra.git
cd pipekit-infra

# 2. Infrastructure + cluster + postgres + secret
cd tofu
tofu init
tofu apply
cd ..

# 3. ArgoCD
kubectl create namespace argocd
kubectl apply --server-side -k argocd/argocd/
kubectl wait --for=condition=available deployment --all -n argocd --timeout=120s

# 4. PostgREST
kubectl apply -f argocd/postgrest-app.yaml

# 5. Wait for pod
kubectl get pods -n postgrest -w
```

---

## Verify

```bash
# Postgres superuser
docker exec postgres-infra-takehome psql -U postgres -c "\du postgrest_user"

# Secret
kubectl get secret postgrest-secret -n postgrest -o jsonpath='{.data.db-uri}' | base64 -d

# ArgoCD sync status
kubectl get application postgrest -n argocd

# All postgrest resources
kubectl get pods,svc,ingress,jobs -n postgrest

# Data
curl http://localhost:8080/employees
```

---

## Teardown

```bash
cd tofu
tofu destroy
```
