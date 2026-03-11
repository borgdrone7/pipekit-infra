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

`depends_on = [docker_container.postgres]` tells OpenTofu to wait until the container *resource* is created. But "container created" in Docker terms means the container process started — not that the application inside it is ready. The gap between Docker saying "container is running" and Postgres saying "I am ready to accept connections" can be several seconds.

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

## Step 2 — coming next

Injecting the `postgrest_user` credentials as a Kubernetes Secret into the `postgrest` namespace via OpenTofu.
