# Dify Helm Chart

Status: implementation preview. Helm rendering is tested; a Kubernetes installation,
Rancher UI installation, business workflows, and network enforcement still require
the runtime acceptance checks below. Do not treat a successful render as production
certification.

## Install

Requirements: Helm 3, Kubernetes 1.26+ APIs, a working CSI provisioner, a default
StorageClass (or `persistence.storageClass`), and a NetworkPolicy-capable CNI such
as Calico or Cilium. The minimum Kubernetes version describes API compatibility,
not a tested runtime support matrix. Image architectures and registry access must
be checked for your cluster, particularly the Compose plugin `0.6.10-local` tag.

From the parent of this repository:

```sh
helm install dify ./helm/dify -n dify --create-namespace \
  --wait --wait-for-jobs --timeout 35m
kubectl -n dify port-forward service/dify-dify-nginx 8080:80
```

Open `http://localhost:8080` and complete administrator setup. No model-provider
credentials are bundled. Public webhooks cannot reach a local port-forward.

When running inside the standalone `helm` repository, replace `./helm/dify` with
`./dify`. No dependency downloads are required for the default installation.

For public access, start from `ci/ingress.yaml`; change the hostname, IngressClass,
and TLS Secret. Its existingSecret entry is an example, not a mandatory requirement
for an online Helm installation. cert-manager can issue the referenced Secret via
your own Ingress issuer annotation; the chart does not install cert-manager.
Configure controller upload and long-connection timeouts for SSE and WebSockets.
Set `exposure.trustedProxyCidrs` only to actual proxy source ranges to recover the
client IP. Without that explicit trust, the API sees the ingress proxy IP. Never
use `0.0.0.0/0`. Forwarded protocol is derived from the TLS configuration, not an
untrusted request header. Prevent direct access to the backend gateway when using
an Ingress that terminates TLS.

## Deployment and Storage

Default compact mode runs API, WebSocket (port 5006), worker, and singleton Beat in
one Pod with a shared RWO PVC and Recreate updates. This trades availability and
independent scaling for compatibility with ordinary RWO storage. Split mode uses
one Deployment per process and requires RWX for application files. Merely pointing
uploads at S3 does not prove every local directory can stop being shared.

Web, Nginx, the two Squid proxies, and Agent Backend are Deployments. PostgreSQL,
Redis (AOF enabled), Weaviate, Plugin Daemon, and Local Sandbox are singleton
StatefulSets. The local sandbox has separate home/workspace claims. Initial volume
size defaults to 10Gi **per claim**, not total. `persistence.existingClaim` replaces
only the application PVC. Other services create their own RWO claims. Verify CSI
ownership behavior; application and plugin/sandbox volumes use fsGroup 1001.

Neither internal dependencies nor the default application stack are HA. All
replicas are intentionally fixed to one until shared state and routing are tested.
Scale through reviewed chart changes, not an untested generic replicas override.
Resources and scheduling use `resources`, `nodeSelector`, `tolerations`, `affinity`.
Size resources for each actual workload before production; the chart does not
pretend one set of resource limits fits every database and sandbox execution.

## Credentials

Online Helm creates an annotated, retained Secret and reuses it through `lookup`
on upgrades. Back it up before uninstalling. Keep the same release and namespace
when reusing retained resources. Do not delete credentials while retaining data.
Do not expect `helm template` to query the cluster. Offline/GitOps users **must**
set `security.existingSecret`; otherwise every render generates new credentials.
For Argo CD, Flux, External Secrets, or SOPS, manage the Secret separately and
provide only its name to Helm. Password inputs in a UI are not encryption.

The Secret must contain nonempty values under these exact keys:

| Key | Consumers / format |
| --- | --- |
| SECRET_KEY | API encryption/signing; preserve with application data |
| DB_PASSWORD | PostgreSQL and plugin database |
| REDIS_PASSWORD | Redis cache, Celery, Agent; use URL-safe characters in this version |
| WEAVIATE_API_KEY | Weaviate and API |
| CODE_EXECUTION_API_KEY | API and code sandbox |
| PLUGIN_DAEMON_KEY | API/Agent to Plugin Daemon |
| INNER_API_KEY_FOR_PLUGIN | Plugin/Agent to API |
| AGENT_BACKEND_API_TOKEN | API/worker to Agent |
| DIFY_AGENT_SERVER_SECRET_KEY | Exactly 32 random bytes encoded as unpadded Base64URL |
| SHELLCTL_AUTH_TOKEN | Agent to Local Sandbox |

All keys are required even when Agent is disabled, keeping the Secret contract
stable when it is re-enabled. The generated values meet these requirements.
The sandbox receives only its own key; it does not receive database credentials.

`ci/external.yaml` demonstrates externally managed PostgreSQL, Redis, and Weaviate.
Precreate the application and plugin databases and grant appropriate migration
permissions. This release does not support Redis ACL usernames, Redis TLS, or
PostgreSQL TLS configuration; do not use these examples where encryption in
transit is mandatory. External Weaviate needs both HTTP and gRPC endpoints.

## Configuration and Upgrades

Internal DNS, service URLs, callbacks, and WebSocket URLs derive from release and
entrypoint configuration. Non-Ingress access uses `exposure.publicUrl`, including
the externally reachable port. `extraEnv` configures advanced shared application
settings; chart-managed identity/connection settings are rejected on conflict.
`extraEnvFrom` is loaded before chart configuration/credentials and cannot replace
them. Do not put sensitive values in a ConfigMap; use external Secret references.
Every `images` entry can be replaced with a mirror or digest, and private registry
credentials are configured with `imagePullSecrets`.

A revision-specific ordinary Job waits for PostgreSQL, creates the plugin database
for internal installations when necessary, then runs `flask upgrade-db` through
the API image's migration entrypoint. Core init containers poll that specific Job
using a namespace-scoped, read-only, projected token; runtime containers cannot
access the token. Other processes do not rerun API migrations. Plugin Daemon owns
its own schema lifecycle and may restart while its database is being prepared.

Back up database, application, plugin, Agent volumes and the credentials Secret
before each upgrade. Test schema compatibility with old instances: an ordinary
Job is not a universal zero-downtime migration protocol. Upgrade only through
supported Dify version paths. `helm rollback` cannot undo database migrations;
do not use automatic rollback as a database recovery procedure.

Keep migration Jobs while any Pod's init template still refers to that revision,
including restart and rollback candidates. There is deliberately no TTL cleanup.
If a migration fails, inspect its logs and database state. Retry through a new Helm
revision after fixing the cause. Do not blindly delete or retry destructive changes.
Immutable StatefulSet claim settings cannot be changed by ordinary Helm upgrades;
volume expansion/replacement requires a separate CSI-aware procedure.

## Network Boundary

Sandbox NetworkPolicies default to ingress/egress isolation. Code Sandbox can only
reach DNS and the standard Squid proxy. Local Sandbox can reach DNS, Agent Backend
5050, and its own proxy 3128. Only the Agent Backend can connect to Shellctl 5004.
Direct API, database, metadata service, and public internet access from the sandbox
are denied when the CNI enforces policy. Arbitrary shell execution still has direct
access to the Agent Backend: this is the same known control-network limitation
as Compose, not complete tenant isolation.

Squid allows public destinations and denies private/loopback/link-local targets.
The Agent proxy additionally permits the Agent `/agent-stub/` and API `/files/`
paths. `proxy.allowedPrivateCidrs` and `allowedPrivateDomains` explicitly relax
that policy for both proxies; leave empty unless needed. NodeLocal DNS users must
configure `networkPolicy.extraDnsCidrs` with the resolver's /32 or /128. Pod-based
DNS defaults to kube-system pods labeled k8s-app=kube-dns. Policies are additive:
other namespace policies must not grant broad sandbox access.

## Rancher and Publishing

`questions.yaml` provides conditional forms with StorageClass, PVC, and Secret
selectors. Advanced settings remain editable through Values YAML. No Rancher CRDs
are required. The form uses official documented question types, but its target
Rancher version remains uncertified until an actual UI installation is tested.

Publish a standard Helm repository (run from this repository root):

```sh
mkdir -p dist
helm package dify --destination dist
helm repo index dist --url https://charts.example.com/dify
```

Host `dist` over HTTPS and add the URL in Rancher Cluster Repositories. The directory
layout is not a Rancher Git catalog; do not point Rancher at an arbitrary source
subdirectory and expect discovery. OCI distribution is optional and must be checked
against the selected Rancher version.

## Acceptance

Run `ruby dify/tests/validate.rb` from the chart repository when the test suite is
present. CI also validates rendered resources against Kubernetes schemas.

Runtime acceptance requires a disposable cluster with a real CSI and enforcing
CNI: install with `--wait --wait-for-jobs`, restart Pods, upgrade the release and
verify unchanged secrets/data, inspect a failed migration, then test administrator
setup, model plugin installation, SSE chat, knowledge ingestion/retrieval, Celery
tasks, Beat schedules, collaboration, code execution, Agent shell/files, and plugin
callbacks. Verify blocked direct egress and successful allowed proxied requests
from **both** sandbox types. Provider-dependent workflows require test credentials.

Record actual image versions/architectures, Kubernetes/Rancher/CNI/CSI versions,
and test results before calling a release production-ready.