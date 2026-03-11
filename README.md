# Infrastructure Take Home

Treat this system as a production system.

## Architecture

```
Your Machine
├── Docker Engine
│   ├── k3d → k3s cluster (Kubernetes)
│   │   ├── argocd namespace     → ArgoCD (GitOps — watches this repo)
│   │   ├── postgrest namespace
│   │   │   ├── Secret           (postgres credentials, injected by OpenTofu)
│   │   │   ├── Deployment       (PostgREST pod)
│   │   │   ├── Service          (internal routing)
│   │   │   └── Ingress          (exposed on http://localhost:8080)
│   │   └── Job                  (inserts test data into Postgres)
│   └── postgres container       (port 5432, Docker volume for persistent data)
└── OpenTofu manages everything above
```

> **Why is Postgres outside the cluster?**
> This is intentional. The cluster is stateless and can be destroyed and rebuilt at any time with `tofu destroy` + `tofu apply`. Postgres runs as a Docker container with its own Docker volume so data survives a full cluster rebuild — exactly the same pattern as using an external managed database (RDS, CloudSQL) in production.

---

## Setup Instructions

### Prerequisites

Install the following tools before proceeding.

#### Docker

Required by everything — k3d runs Kubernetes inside Docker containers, and Postgres runs as a Docker container.

```bash
# Ubuntu / Debian
sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl enable --now docker

# Add your user to the docker group (avoid needing sudo)
sudo usermod -aG docker $USER
newgrp docker

# Verify
docker --version
```

For macOS: install [Docker Desktop](https://www.docker.com/products/docker-desktop/).

#### k3d

k3d creates a local Kubernetes cluster by running k3s nodes as Docker containers.

```bash
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Verify
k3d --version
```

#### OpenTofu

OpenTofu is the open-source Terraform fork used to manage all infrastructure as code.

```bash
# Ubuntu / Debian via snap
sudo snap install opentofu --classic

# macOS via Homebrew
brew install opentofu

# Verify
tofu --version
```

#### kubectl

The Kubernetes CLI — used to interact with the cluster.

```bash
# Ubuntu / Debian via snap
sudo snap install kubectl --classic

# macOS via Homebrew
brew install kubectl

# Verify
kubectl version --client
```

#### git

```bash
# Ubuntu / Debian
sudo apt-get install -y git

# macOS (comes pre-installed, or via Homebrew)
brew install git
```

---

### Verified versions used in this setup

| Tool | Version |
|---|---|
| Docker | 28.2.2 |
| k3d | v5.8.3 |
| OpenTofu | v1.11.5 |
| kubectl | v1.34.5 |

---

## Running the Setup

### 1. Clone the repository

```bash
git clone git@github.com:borgdrone7/pipekit-infra.git
cd pipekit-infra
```

### 2. Initialise infrastructure with OpenTofu

This creates the k3d cluster and the Postgres Docker container.

```bash
cd tofu
tofu init
tofu apply
```

Type `yes` when prompted. This will:
- Create a k3d Kubernetes cluster named `infra-takehome`
- Pull and start a Postgres 16 Docker container on port `5432`
- Create a Docker volume for persistent Postgres data
- Create the `postgrest` database
- Create the `postgrest_user` superuser in Postgres
- Create the `postgrest` namespace in Kubernetes
- Inject Postgres credentials as a Kubernetes Secret in the `postgrest` namespace

### 3. Install ArgoCD

```bash
cd ../argocd
kubectl create namespace argocd
kubectl apply --server-side -k argocd/
```

Wait for ArgoCD to be ready:

```bash
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s
```

### 4. Deploy PostgREST via ArgoCD

Apply the ArgoCD Application manifest — ArgoCD will pick it up and deploy PostgREST automatically:

```bash
kubectl apply -f argocd/postgrest-app.yaml
```

Watch the sync:

```bash
kubectl get pods -n postgrest -w
```

### 5. Verify the endpoint

Once pods are running, visit:

```
http://localhost:8080
```

You should see the PostgREST JSON response with the data injected by the Job.

---

## Teardown

To destroy the cluster and all Kubernetes resources:

```bash
cd tofu
tofu destroy
```

This removes the k3d cluster. The Postgres Docker container and its data volume are also removed. Re-run `tofu apply` to start fresh.

---

## Expected Result

<!-- Screenshot will be added after final step -->

---

# Original Task

## Problem

Please add commits to your fork of the repo to answer this problem.
Note: the use of the word `postgrest` is confusing, but correct - this is a project that we're going to deploy.

## Add a user to the database

Please add a super user to the postgrest database.

## Inject a secret for postgrest

Creating a superuser account in this new database, inject the secrets into the k3d cluster into a namespace called postgrest.
You must do this with terraform/opentofu.

## Install Postgrest into the k3d cluster

https://docs.postgrest.org/en/v14/

The result should be an accessible endpoint that you can use in your browser.

## Inject some data from the cluster using a `Job`

Use a kubernetes job to inject some data into the postgres database

## Provide an expected screenshot

Update this file, README.md, with a screenshot of what we should see when we visit the URL after following your instructions - this should show us the data you have injected.
