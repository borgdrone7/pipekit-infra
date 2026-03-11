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

Postgres runs as a Docker container rather than inside Kubernetes. This is intentional — architecturally the database is independent from the cluster (different technology, different network, different lifecycle concern). In production this would be a managed service (RDS, CloudSQL) or a database operator like CloudNativePG with a PersistentVolumeClaim backed by a cloud StorageClass. Either way, the principle is the same: the database lifecycle should be independent from the cluster lifecycle.

**Note on `tofu destroy` in this setup:**

Because the task provides a single `tofu` directory managing both the cluster and Postgres, running `tofu destroy` destroys everything — including the Postgres container and its data volume. This means DB data does not survive a full destroy in this setup.

In a real production system you would split these into two separate OpenTofu states:

```
tofu/database/   ← manages only Postgres — destroy independently
tofu/cluster/    ← manages only the k3d cluster — can be wiped freely
```

This would give true lifecycle independence. For this task a single tofu state is used because the task specifies one `tofu` directory for both, keeping things simple and reproducible in one command.

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
git clone https://github.com/borgdrone7/pipekit-infra.git
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
cd ..
kubectl create namespace argocd
kubectl apply --server-side -k argocd/argocd/
kubectl wait --for=condition=available deployment --all -n argocd --timeout=120s
```

### 4. Deploy PostgREST via ArgoCD

```bash
kubectl apply -f argocd/postgrest-app.yaml
```

Watch until the pod is running:

```bash
kubectl get pods -n postgrest -w
```

### 5. Verify the endpoint

```bash
curl http://localhost:8080/employees
```

You should see JSON with the seeded employee data.

---

## Teardown

```bash
cd tofu
tofu destroy
```

Removes everything managed by OpenTofu: the k3d cluster, the Postgres container, and its data volume. All database data is lost. Re-run `tofu apply` to start completely fresh — the seed Job will recreate the table and data automatically via ArgoCD.

---

## Expected Result

![PostgREST employees endpoint showing injected data](screenshot.png)
