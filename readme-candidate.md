# Setup Instructions

## Architecture

```
Your Machine
├── Docker Engine
│   ├── k3d -> k3s cluster (Kubernetes)
│   │   ├── argocd namespace     -> ArgoCD (GitOps, watches this repo)
│   │   ├── postgrest namespace
│   │   │   ├── Secret           (postgres credentials, injected by OpenTofu)
│   │   │   ├── Deployment       (PostgREST pod)
│   │   │   ├── Service          (internal routing)
│   │   │   └── Ingress          (exposed on http://localhost:8080)
│   │   └── Job                  (inserts test data into Postgres)
│   └── postgres container       (port 5432, Docker volume for persistent data)
└── OpenTofu manages everything above
```

**Why is Postgres outside the cluster?**

The cluster is stateless and can be destroyed and rebuilt at any time with `tofu destroy` + `tofu apply`. Postgres runs as a Docker container with its own Docker volume so data survives a full cluster rebuild. In production this would be replaced by a managed service (RDS, CloudSQL) or a database operator such as CloudNativePG running inside the cluster with a PersistentVolumeClaim backed by a cloud StorageClass. Either way, the principle is the same: the database lifecycle is independent from the cluster lifecycle.

---

## Prerequisites

Install the following tools before proceeding.

### Docker

Required by everything. k3d runs Kubernetes nodes as Docker containers, and Postgres itself runs as a Docker container.

```bash
# Ubuntu / Debian
sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl enable --now docker

# Add your user to the docker group (avoid needing sudo for docker commands)
sudo usermod -aG docker $USER
newgrp docker

# Verify
docker --version
```

For macOS: install [Docker Desktop](https://www.docker.com/products/docker-desktop/).

### k3d

Creates a local Kubernetes cluster by running k3s nodes as Docker containers.

```bash
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

# Verify
k3d --version
```

### OpenTofu

Open-source Terraform fork used to manage all infrastructure as code.

```bash
# Ubuntu / Debian
sudo snap install opentofu --classic

# macOS
brew install opentofu

# Verify
tofu --version
```

### kubectl

The Kubernetes CLI used to interact with the cluster.

```bash
# Ubuntu / Debian
sudo snap install kubectl --classic

# macOS
brew install kubectl

# Verify
kubectl version --client
```

### git

```bash
# Ubuntu / Debian
sudo apt-get install -y git

# macOS (pre-installed, or via Homebrew)
brew install git
```

---

### Verified versions

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

```bash
cd tofu
tofu destroy
```

Removes the k3d cluster, the Postgres container, and its data volume. Re-run `tofu apply` to start fresh.

---

## Expected Result

<!-- Screenshot will be added after final step -->
