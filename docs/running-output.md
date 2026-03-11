# Running Output

Complete output from a fresh run on a machine where all prerequisites are already installed.
Commands are exactly as listed in `running-short.md`.

---

## Step 2 — Infrastructure

```
$ cd tofu
$ tofu init

Initializing the backend...

Initializing provider plugins...
- terraform.io/builtin/terraform is built in to OpenTofu
- Reusing previous version of kreuzwerker/docker from the dependency lock file
- Reusing previous version of cyrilgdn/postgresql from the dependency lock file
- Using previously-installed kreuzwerker/docker v3.9.0
- Using previously-installed cyrilgdn/postgresql v1.26.0

OpenTofu has been successfully initialized!
```

```
$ tofu apply
... (plan output) ...

Plan: 8 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + cluster_name               = "infra-takehome"
  + postgres_connection_string = (sensitive value)
  + postgres_host              = "localhost"
  + postgres_port              = 5432

Do you want to perform these actions?
  Only 'yes' will be accepted to approve.

  Enter a value: yes

terraform_data.k3d_cluster: Creating...
terraform_data.k3d_cluster: Provisioning with 'local-exec'...
terraform_data.k3d_cluster (local-exec): Executing: ["/bin/sh" "-c" "k3d cluster create infra-takehome --image rancher/k3s:v1.35.2-k3s1 --servers 1 --agents 0 -p '8080:80@loadbalancer'"]
docker_volume.postgres_data: Creating...
docker_image.postgres: Creating...
docker_volume.postgres_data: Creation complete after 0s [id=postgres-infra-takehome-data]
terraform_data.k3d_cluster (local-exec): INFO Prep: Network
docker_image.postgres: Creation complete after 0s [id=sha256:108b27c9...postgres:16-alpine]
docker_container.postgres: Creating...
terraform_data.k3d_cluster (local-exec): INFO Created network 'k3d-infra-takehome'
terraform_data.k3d_cluster (local-exec): INFO Created image volume k3d-infra-takehome-images
terraform_data.k3d_cluster (local-exec): INFO Starting new tools node...
terraform_data.k3d_cluster (local-exec): INFO Starting node 'k3d-infra-takehome-tools'
terraform_data.k3d_cluster (local-exec): INFO Creating node 'k3d-infra-takehome-server-0'
terraform_data.k3d_cluster (local-exec): INFO Creating LoadBalancer 'k3d-infra-takehome-serverlb'
terraform_data.k3d_cluster (local-exec): INFO Using the k3d-tools node to gather environment information
terraform_data.k3d_cluster (local-exec): INFO HostIP: using network gateway 172.28.0.1 address
terraform_data.k3d_cluster (local-exec): INFO Starting cluster 'infra-takehome'
terraform_data.k3d_cluster (local-exec): INFO Starting servers...
terraform_data.k3d_cluster (local-exec): INFO Starting node 'k3d-infra-takehome-server-0'
docker_container.postgres: Creation complete after 4s [id=366915da...]
postgresql_database.postgrest: Creating...
postgresql_database.postgrest: Creation complete after 0s [id=postgrest]
postgresql_role.postgrest_user: Creating...
postgresql_role.postgrest_user: Creation complete after 0s [id=postgrest_user]
terraform_data.k3d_cluster (local-exec): INFO All agents already running.
terraform_data.k3d_cluster (local-exec): INFO Starting helpers...
terraform_data.k3d_cluster (local-exec): INFO Starting node 'k3d-infra-takehome-serverlb'
terraform_data.k3d_cluster: Still creating... [10s elapsed]
terraform_data.k3d_cluster (local-exec): INFO Injecting records for hostAliases (incl. host.k3d.internal) and for 2 network members into CoreDNS configmap...
terraform_data.k3d_cluster (local-exec): INFO Cluster 'infra-takehome' created successfully!
terraform_data.k3d_cluster (local-exec): INFO You can now use it like this:
terraform_data.k3d_cluster (local-exec): kubectl cluster-info
terraform_data.k3d_cluster: Creation complete after 13s [id=dab542ee...]
terraform_data.postgrest_namespace: Creating...
terraform_data.postgrest_namespace (local-exec): Executing: kubectl create namespace postgrest ... | kubectl apply ...
terraform_data.postgrest_namespace (local-exec): namespace/postgrest created
terraform_data.postgrest_namespace: Creation complete after 0s [id=f78c4420...]
terraform_data.postgrest_secret: Creating...
terraform_data.postgrest_secret (local-exec): (output suppressed due to sensitive value in config)
terraform_data.postgrest_secret: Creation complete after 0s [id=971fddd2...]

Apply complete! Resources: 8 added, 0 changed, 0 destroyed.

Outputs:

cluster_name = "infra-takehome"
postgres_connection_string = <sensitive>
postgres_host = "localhost"
postgres_port = 5432
```

---

## Step 3 — ArgoCD

```
$ cd ..
$ kubectl create namespace argocd
namespace/argocd created

$ kubectl apply --server-side -k argocd/argocd/
customresourcedefinition.apiextensions.k8s.io/applications.argoproj.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/applicationsets.argoproj.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/appprojects.argoproj.io serverside-applied
serviceaccount/argocd-application-controller serverside-applied
serviceaccount/argocd-applicationset-controller serverside-applied
serviceaccount/argocd-dex-server serverside-applied
serviceaccount/argocd-notifications-controller serverside-applied
serviceaccount/argocd-redis serverside-applied
serviceaccount/argocd-repo-server serverside-applied
serviceaccount/argocd-server serverside-applied
role.rbac.authorization.k8s.io/argocd-application-controller serverside-applied
role.rbac.authorization.k8s.io/argocd-applicationset-controller serverside-applied
role.rbac.authorization.k8s.io/argocd-dex-server serverside-applied
role.rbac.authorization.k8s.io/argocd-notifications-controller serverside-applied
role.rbac.authorization.k8s.io/argocd-redis serverside-applied
role.rbac.authorization.k8s.io/argocd-server serverside-applied
clusterrole.rbac.authorization.k8s.io/argocd-application-controller serverside-applied
clusterrole.rbac.authorization.k8s.io/argocd-applicationset-controller serverside-applied
clusterrole.rbac.authorization.k8s.io/argocd-server serverside-applied
rolebinding.rbac.authorization.k8s.io/argocd-application-controller serverside-applied
rolebinding.rbac.authorization.k8s.io/argocd-applicationset-controller serverside-applied
rolebinding.rbac.authorization.k8s.io/argocd-dex-server serverside-applied
rolebinding.rbac.authorization.k8s.io/argocd-notifications-controller serverside-applied
rolebinding.rbac.authorization.k8s.io/argocd-redis serverside-applied
rolebinding.rbac.authorization.k8s.io/argocd-server serverside-applied
clusterrolebinding.rbac.authorization.k8s.io/argocd-application-controller serverside-applied
clusterrolebinding.rbac.authorization.k8s.io/argocd-applicationset-controller serverside-applied
clusterrolebinding.rbac.authorization.k8s.io/argocd-server serverside-applied
configmap/argocd-cm serverside-applied
configmap/argocd-cmd-params-cm serverside-applied
configmap/argocd-gpg-keys-cm serverside-applied
configmap/argocd-notifications-cm serverside-applied
configmap/argocd-rbac-cm serverside-applied
configmap/argocd-ssh-known-hosts-cm serverside-applied
configmap/argocd-tls-certs-cm serverside-applied
secret/argocd-notifications-secret serverside-applied
secret/argocd-secret serverside-applied
service/argocd-applicationset-controller serverside-applied
service/argocd-dex-server serverside-applied
service/argocd-metrics serverside-applied
service/argocd-notifications-controller-metrics serverside-applied
service/argocd-redis serverside-applied
service/argocd-repo-server serverside-applied
service/argocd-server serverside-applied
service/argocd-server-metrics serverside-applied
deployment.apps/argocd-applicationset-controller serverside-applied
deployment.apps/argocd-dex-server serverside-applied
deployment.apps/argocd-notifications-controller serverside-applied
deployment.apps/argocd-redis serverside-applied
deployment.apps/argocd-repo-server serverside-applied
deployment.apps/argocd-server serverside-applied
statefulset.apps/argocd-application-controller serverside-applied
networkpolicy.networking.k8s.io/argocd-application-controller-network-policy serverside-applied
networkpolicy.networking.k8s.io/argocd-applicationset-controller-network-policy serverside-applied
networkpolicy.networking.k8s.io/argocd-dex-server-network-policy serverside-applied
networkpolicy.networking.k8s.io/argocd-notifications-controller-network-policy serverside-applied
networkpolicy.networking.k8s.io/argocd-redis-network-policy serverside-applied
networkpolicy.networking.k8s.io/argocd-repo-server-network-policy serverside-applied
networkpolicy.networking.k8s.io/argocd-server-network-policy serverside-applied

$ kubectl wait --for=condition=available deployment --all -n argocd --timeout=120s
deployment.apps/argocd-applicationset-controller condition met
deployment.apps/argocd-dex-server condition met
deployment.apps/argocd-notifications-controller condition met
deployment.apps/argocd-redis condition met
deployment.apps/argocd-repo-server condition met
deployment.apps/argocd-server condition met
```

---

## Step 4 — PostgREST

```
$ kubectl apply -f argocd/postgrest-app.yaml
application.argoproj.io/postgrest created
```

---

## Step 5 — Wait for pod

```
$ kubectl get pods -n postgrest -w
NAME                         READY   STATUS              RESTARTS   AGE
postgrest-6787f574f8-xgnlr   1/1     Running             0          6s
seed-data-77zcp              0/1     ContainerCreating   0          6s
seed-data-77zcp              0/1     Completed           0          15s
```

---

## Verify

```
$ curl http://localhost:8080/employees
[{"id":1,"name":"Alice Johnson","role":"Senior Engineer","department":"Platform"},
 {"id":2,"name":"Bob Smith","role":"DevOps Engineer","department":"Infrastructure"},
 {"id":3,"name":"Carol White","role":"Product Manager","department":"Product"},
 {"id":4,"name":"Dan Lee","role":"Security Engineer","department":"Security"}]
```

---

## Teardown

```
$ cd tofu
$ tofu destroy

...

Destroy complete! Resources: 8 destroyed.
```
