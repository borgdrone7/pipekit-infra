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

# k3d merges the cluster kubeconfig into ~/.kube/config automatically.
# config_context pins the provider to this specific cluster so it does not
# accidentally talk to a different cluster if multiple contexts exist.
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "k3d-${var.k3d_cluster_name}"
}

resource "kubernetes_namespace" "postgrest" {
  metadata {
    name = "postgrest"
  }

  depends_on = [terraform_data.k3d_cluster]
}

resource "kubernetes_secret" "postgrest" {
  metadata {
    name      = "postgrest-secret"
    namespace = kubernetes_namespace.postgrest.metadata[0].name
  }

  # host.k3d.internal is a hostname k3d injects into every pod's /etc/hosts.
  # It resolves to the host machine IP so pods can reach services running
  # outside the cluster — in this case the Postgres Docker container.
  data = {
    db-uri = "postgresql://postgrest_user:${var.postgrest_user_password}@host.k3d.internal:${var.postgres_port}/postgrest"
  }
}
