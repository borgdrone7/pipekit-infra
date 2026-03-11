# Running Notes

This file documents what actually happened when running each step, including problems hit and why certain decisions were made. Useful for anyone reproducing this or understanding the reasoning behind non-obvious configuration.

---

## Step 1 — OpenTofu: Postgres container, superuser, k3d cluster

### What this step does

Running `tofu apply` from the `tofu/` directory creates everything in one shot:

- A k3d Kubernetes cluster named `infra-takehome` with port `8080` on your machine mapped to the cluster load balancer
- A Postgres 16 Docker container on port `5432` with a persistent Docker volume
- A `postgrest` database inside Postgres
- A `postgrest_user` superuser role inside Postgres

### How to run

```bash
cd tofu
tofu init
tofu apply
```

Type `yes` when prompted. Expected output ends with:

```
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.
```

### Verify the superuser was created

```bash
docker exec postgres-infra-takehome psql -U postgres -c "\du postgrest_user"
```

Expected output:

```
      Role name    |       Attributes
  ----------------+-------------------------------
   postgrest_user | Superuser
                  | Password valid until infinity
```

---

## Problem hit: Postgres not ready when OpenTofu tried to connect

### What happened

On the first run, `tofu apply` failed with:

```
Error: error connecting to PostgreSQL server localhost:
read: connection reset by peer
```

The Docker container started successfully but the PostgreSQL process inside it takes a few seconds to initialise its data directory and start accepting connections. OpenTofu saw the container as "created" and immediately tried to connect via the `postgresql` provider to create the database and role — before Postgres was actually ready.

This is a very common problem with any tool that provisions a database container and then immediately tries to use it.

### Why `depends_on` alone does not solve it

`depends_on = [docker_container.postgres]` tells OpenTofu to wait until the container *resource* is created. But there are three different stages inside a container that must not be confused:

| Stage | What it means |
|---|---|
| 1. Container started | Docker process is running — the OS inside the container is up |
| 2. Postgres process started | The `postgres` binary launched and is initialising the data directory |
| 3. Postgres ready | Data directory initialised, server is listening and accepting connections |

`depends_on` only guarantees stage 1. The gap between stage 1 and stage 3 can be several seconds — long enough for OpenTofu to attempt a connection and fail.

### The fix: healthcheck + `wait = true`

We added a healthcheck to the Docker container resource and set `wait = true`:

```hcl
healthcheck {
  test     = ["CMD-SHELL", "pg_isready -U postgres"]
  interval = "2s"
  timeout  = "5s"
  retries  = 15
}

wait         = true
wait_timeout = 60
```

- `pg_isready` is the official Postgres tool for checking if the server is accepting connections. It is included in the Postgres Docker image.
- `wait = true` tells the OpenTofu Docker provider to block at this resource until the healthcheck reports healthy. Only then does OpenTofu mark the container as created and proceed to dependent resources.
- With this in place, `postgresql_database` and `postgresql_role` never attempt to connect until Postgres is genuinely ready.

The result is a clean single-run `tofu apply` with no manual retries needed.

---

---

## ArgoCD installation

This is part of the original starting point — install ArgoCD into the cluster after `tofu apply`.

### What this step does

Applies all ArgoCD Kubernetes objects (Deployments, Services, RBAC, CRDs, ConfigMaps, Secrets, NetworkPolicies) into the `argocd` namespace using Kustomize. The `kustomization.yaml` pulls the official ArgoCD install manifest directly from GitHub and applies it.

### How to run

```bash
kubectl create namespace argocd
kubectl apply --server-side -k argocd/argocd/
```

The `--server-side` flag is required here because ArgoCD's install manifest contains large objects (CRDs) that exceed the size limit of the default client-side apply. Server-side apply pushes the computation to the cluster instead of the local kubectl client.

Wait for ArgoCD to be fully ready:

```bash
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s
```

Verify all pods are running:

```bash
kubectl get pods -n argocd
```

Expected: 7 pods all in `Running` state.

---

---

## Step 2 — OpenTofu: postgrest namespace and Kubernetes Secret

### What this step does

Adds the `kubernetes` provider to OpenTofu and creates two resources in the k3d cluster:
- A `postgrest` namespace
- A `postgrest-secret` Secret containing the Postgres connection string for PostgREST

### How to run

This step is part of the same `tofu apply` as step 1. After adding the kubernetes provider, run:

```bash
cd tofu
tofu init   # needed once to download the new kubernetes provider
tofu apply
```

Expected output includes:

```
kubernetes_namespace.postgrest: Creation complete
kubernetes_secret.postgrest: Creation complete
```

### Verify the secret

```bash
kubectl get secret postgrest-secret -n postgrest -o jsonpath='{.data.db-uri}' | base64 -d
```

Expected output:

```
postgresql://postgrest_user:postgrest_password@host.k3d.internal:5432/postgrest
```

### Why `host.k3d.internal` and not `localhost`?

PostgREST runs as a pod inside the k3d cluster. Postgres runs as a Docker container on the host machine, outside the cluster.

Inside a pod, `localhost` refers to the pod itself — not your machine. `host.k3d.internal` is a hostname k3d automatically injects into every pod's `/etc/hosts` file. It resolves to the host machine's IP inside the Docker network. This is the bridge between the two.

The OpenTofu `postgresql` provider uses `localhost` because it runs on your machine and the Postgres port is mapped to your machine. Two different network contexts, two different addresses for the same Postgres container.

### Why `.terraform.lock.hcl` was fixed in .gitignore

The original `.gitignore` excluded `.terraform.lock.hcl`. This was incorrect — the lock file records the exact provider versions downloaded and must be committed so all contributors get identical versions on `tofu init`. Without it, someone on a different machine might get a different provider version and hit unexpected behaviour.

---

## Step 3 — Deploy PostgREST via ArgoCD

### What this step does

Creates the PostgREST manifests in `postgrest/` and an ArgoCD Application in `argocd/postgrest-app.yaml`. ArgoCD pulls the manifests from GitHub and deploys them automatically.

### Important: push before applying

ArgoCD pulls manifests from Git, not from your local machine. Push first, then apply the Application — otherwise ArgoCD cannot find the manifests.

```bash
git add postgrest/ argocd/postgrest-app.yaml
git push
kubectl apply -f argocd/postgrest-app.yaml
```

Verify ArgoCD synced and the pod is running:

```bash
kubectl get application postgrest -n argocd
kubectl get pods,svc,ingress -n postgrest
```

Expected:

```
NAME        SYNC STATUS   HEALTH STATUS
postgrest   Synced        Healthy

NAME                        READY   STATUS
pod/postgrest-xxx           1/1     Running

NAME                                  CLASS     HOSTS   ADDRESS
ingress.networking.k8s.io/postgrest   traefik   *       172.x.x.x
```

Verify the endpoint:

```bash
curl http://localhost:8080
```

Should return a JSON OpenAPI spec. No tables appear yet — that is expected. Data is injected in the next step.

---

## Step 4 — Kubernetes Job: seed data

### What this step does

A Job runs a `postgres:16-alpine` pod once to completion. It connects to Postgres via the same Secret PostgREST uses, creates an `employees` table, and inserts four rows. The SQL uses `IF NOT EXISTS` and `ON CONFLICT DO NOTHING` so the Job is safe to run multiple times without duplicating data.

### How to run

The Job is in `postgrest/job-seed.yaml` and listed in `kustomization.yaml` — ArgoCD deploys it automatically on sync. No manual step needed beyond pushing the file.

Force an immediate sync if needed:

```bash
kubectl annotate application postgrest -n argocd argocd.argoproj.io/refresh="normal" --overwrite
```

Verify the Job completed:

```bash
kubectl get jobs,pods -n postgrest
```

Expected:

```
NAME                  STATUS     COMPLETIONS   DURATION
job.batch/seed-data   Complete   1/1           16s

NAME                        READY   STATUS
pod/postgrest-xxx           1/1     Running
pod/seed-data-xxx           0/1     Completed
```

Verify the data via PostgREST:

```bash
curl http://localhost:8080/employees
```

Expected:

```json
[
  {"id":1,"name":"Alice Johnson","role":"Senior Engineer","department":"Platform"},
  {"id":2,"name":"Bob Smith","role":"DevOps Engineer","department":"Infrastructure"},
  {"id":3,"name":"Carol White","role":"Product Manager","department":"Product"},
  {"id":4,"name":"Dan Lee","role":"Security Engineer","department":"Security"}
]
```

### Why a completed Job is not re-run by ArgoCD

ArgoCD syncs by running the equivalent of `kubectl apply` on every manifest. `kubectl apply` is declarative — it means "make the cluster match this definition", not "run this again."

When ArgoCD applies `job-seed.yaml` and the Job already exists in `Completed` state, Kubernetes sees nothing has changed and does nothing. The Job is not deleted, not recreated, not re-triggered.

The only way a completed Job runs again is if it gets deleted. We deliberately avoid `ttlSecondsAfterFinished` on the Job for this reason — that field auto-deletes the Job after N seconds, which would cause ArgoCD to recreate it (and re-run it) on every sync.
