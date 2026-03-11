provider "docker" {}

resource "terraform_data" "k3d_cluster" {
  input = {
    name  = var.k3d_cluster_name
    image = "rancher/k3s:${var.k3s_version}"
  }

  provisioner "local-exec" {
    command = "k3d cluster create ${self.input.name} --image ${self.input.image} --servers 1 --agents 0 -p '8080:80@loadbalancer'"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "k3d cluster delete ${self.input.name}"
  }
}

resource "docker_image" "postgres" {
  name         = "postgres:16-alpine"
  keep_locally = true
}

resource "docker_container" "postgres" {
  name  = "postgres-infra-takehome"
  image = docker_image.postgres.image_id

  env = [
    "POSTGRES_PASSWORD=${var.postgres_password}",
    "POSTGRES_DB=app",
  ]

  ports {
    internal = 5432
    external = var.postgres_port
  }

  volumes {
    volume_name    = docker_volume.postgres_data.name
    container_path = "/var/lib/postgresql/data"
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U postgres"]
    interval = "2s"
    timeout  = "5s"
    retries  = 15
  }

  # wait = true makes OpenTofu block until the healthcheck passes before
  # marking this resource as created — so postgresql_database and
  # postgresql_role never attempt to connect before Postgres is ready
  wait         = true
  wait_timeout = 60
  restart      = "unless-stopped"
}

resource "docker_volume" "postgres_data" {
  name = "postgres-infra-takehome-data"
}

provider "postgresql" {
  host     = "localhost"
  port     = var.postgres_port
  username = "postgres"
  password = var.postgres_password
  sslmode  = "disable"
}

resource "postgresql_database" "postgrest" {
  name       = "postgrest"
  depends_on = [docker_container.postgres]
}

resource "postgresql_role" "postgrest_user" {
  name       = "postgrest_user"
  login      = true
  superuser  = true
  password   = var.postgrest_user_password
  depends_on = [postgresql_database.postgrest]

  # skip_drop_role prevents OpenTofu from running DROP ROLE on destroy.
  # The role owns objects created by the seed Job (e.g. the employees table).
  # Dropping a role that owns objects fails unless all objects are reassigned first.
  # Since the entire Postgres container is destroyed alongside this role,
  # explicitly dropping it inside Postgres is unnecessary.
  skip_drop_role = true
}

# Using kubectl via local-exec instead of the kubernetes provider.
# The kubernetes provider validates the kubeconfig context at initialization
# time — before any resources run — which causes it to fail on a fresh machine
# where the k3d cluster does not exist yet. kubectl runs during apply, after
# the cluster is created, so this ordering problem does not exist.
# To keep the kubernetes provider, you would need to run:
#   tofu apply -target=terraform_data.k3d_cluster   (create cluster first)
#   tofu apply                                       (then apply the rest)
# In production this is solved by splitting into separate tofu states
# (tofu/cluster/ then tofu/kubernetes/) so the provider only initialises
# after the cluster already exists.

resource "terraform_data" "postgrest_namespace" {
  depends_on = [terraform_data.k3d_cluster]

  provisioner "local-exec" {
    command = "kubectl create namespace postgrest --context k3d-${var.k3d_cluster_name} --dry-run=client -o yaml | kubectl apply --context k3d-${var.k3d_cluster_name} -f -"
  }
}

resource "terraform_data" "postgrest_secret" {
  # triggers_replace re-runs the provisioner if the connection string changes
  # (e.g. password or port variable is updated)
  triggers_replace = {
    db_uri = "postgresql://postgrest_user:${var.postgrest_user_password}@host.k3d.internal:${var.postgres_port}/postgrest"
  }

  depends_on = [terraform_data.postgrest_namespace]

  provisioner "local-exec" {
    # Pass the URI via env var so it does not appear in shell history
    environment = {
      DB_URI = "postgresql://postgrest_user:${var.postgrest_user_password}@host.k3d.internal:${var.postgres_port}/postgrest"
    }
    # --dry-run=client -o yaml | kubectl apply makes this idempotent —
    # safe to run even if the secret already exists
    command = "kubectl create secret generic postgrest-secret --namespace postgrest --context k3d-${var.k3d_cluster_name} --from-literal=db-uri=$DB_URI --dry-run=client -o yaml | kubectl apply --context k3d-${var.k3d_cluster_name} -f -"
  }
}
