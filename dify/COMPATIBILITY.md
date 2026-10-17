# Implementation and Acceptance Matrix

This is not a claim of runtime certification. All entries below are **template
validated only**. No Kubernetes context was configured during local development.
No Rancher UI, network-enforcing CNI, CSI provisioning, image runtime, or business
workflow acceptance has been executed.

## Implemented

| Component | Bundled deployment | External configuration |
| --- | --- | --- |
| PostgreSQL | StatefulSet, plugin DB bootstrap | Precreated databases |
| MySQL | StatefulSet, plugin DB bootstrap | Precreated databases |
| Redis | StatefulSet, AOF, password | Password authentication, no TLS/ACL user yet |
| Weaviate | StatefulSet | HTTP and gRPC |
| Qdrant | StatefulSet | Native Dify environment keys |
| pgvector | StatefulSet | Native Dify environment keys |
| pgvecto-rs | StatefulSet | Native Dify environment keys |
| Chroma | StatefulSet | Native Dify environment keys |
| Elasticsearch | StatefulSet | Native Dify environment keys |
| OpenSearch | StatefulSet | Native Dify environment keys |
| API / worker / Beat / collaboration | Compact or split | Not an external service adapter |
| Web / Nginx / Plugin Daemon | Workloads and routing | Image/connection overrides as documented |
| Code sandbox / SSRF proxies | Workloads, ACLs, NetworkPolicies | Explicit private-target allowlists |
| Agent Backend / Local Sandbox | Workloads, auth, two persistent volumes | E2B/OpenShell configuration adapters |

## Remaining Plan Scope

These are explicit follow-up implementation items, not silently omitted features.
External client configurations have render coverage; bundled workloads have **not**
been implemented for the entries below and selecting internal mode fails clearly.

| Compose profile | Current route | Bundled work still required |
| --- | --- | --- |
| OceanBase | External | Initialization, health, resource sizing, PVC layout |
| SeekDB | External, OceanBase client settings | Image initialization and compatibility tests |
| Couchbase | External | Prebuilt initialization image, buckets/indexes, health |
| Vastbase | External | Operator-provided licensed image and initialization |
| IRIS | External | Durable directory and initialization scripts |
| Oracle | External | Registry/license requirements and startup SQL |
| Milvus | External | Milvus + etcd + MinIO coordinated persistence/auth |
| openGauss | External | Image privilege requirements and initialization |
| MyScale | External | User configuration and persistence |
| MatrixOne | External | Database/user bootstrap and persistence |
| Elasticsearch Japanese | External | ICU/Kuromoji image build and analyzer test |
| Kibana / OpenSearch Dashboards | Not deployed | Authenticated optional dashboards |
| Unstructured | External endpoint | Bundled service, image pin, resource/probe verification |

Other remaining production work: independent workload replica configuration,
per-component resource profiles, external database/Redis TLS and Redis ACL users,
optional CSI-aware PVC expansion, OpenShell certificate mounts, and testing all
actual runtime/upgrade paths. The current resources setting is shared across
containers; it is not a production capacity model.

## Executed Local Checks

- `helm lint` passed.
- Ruby rendering/assertion matrix passed for 18 vector types, MySQL, external
  dependencies, split mode, disabled features, Agent E2B adapter, invalid
  configurations, and 34 Rancher field mappings.
- Every successful matrix rendering passed strict kubeconform checks against
  Kubernetes 1.26.15, 1.31.0, and 1.34.0 schemas.
- Agent JWE key generation decoded to exactly 32 bytes.
- Stable rendering with an existing Secret was checked.
- Squid `6.6-24.04_edge` tag existence was checked against Docker Hub. Image
  existence does not verify an image can start with this configuration.
- All seven default application/wait image tags (API, Web, plugin, Agent Backend,
   Local Sandbox, code sandbox, curl) returned HTTP 200 from Docker Hub, including
   Plugin Daemon `0.6.10-local`. Architecture and runtime behavior remain untested.
- `helm package` produced `dify-0.1.0.tgz` successfully.

## Required Runtime Acceptance

Use an operator-approved disposable cluster, never an implicitly selected
production context. Record namespace, CSI/CNI, architecture, image digests, and
Kubernetes/Rancher versions with results.

1. Install the default chart with `--wait --wait-for-jobs --timeout 35m`.
2. Verify all claims are Bound, migration Job completes, and administrator setup
   loads through both port-forward and the selected Ingress controller.
3. Restart application, plugin, database, and Local Sandbox Pods. Confirm all
   uploaded files, database rows, plugins, home snapshots, and workspaces remain.
4. Save Secret fingerprints without logging plaintext, upgrade, and compare them.
   Test retained Secret/PVC reinstall using the same release/namespace and actual
   Helm ownership behavior. Do not assume a keep annotation alone proves recovery.
5. Inject a database connectivity/migration failure. Confirm the new core Pod does
   not start and an operator can diagnose failure without exposing credentials.
6. Test plugin installation, SSE model chat, knowledge ingestion/retrieval, Celery
   tasks, singleton Beat schedules, collaboration, code execution, Agent shell and
   file upload/download, and plugin `/e/` callbacks with test provider credentials.
7. From each sandbox, prove direct API/database/public/metadata egress is blocked;
   prove required proxied paths and public internet requests succeed. Check
   disallowed private targets and Agent proxy path restrictions fail.
8. Test the Rancher form's resource selectors, conditional visibility, values
   preservation, and install/upgrade. Field mapping tests do not substitute for UI.
9. Run vector insert/search/delete integration tests for each advertised backend.
   Validate external E2B/OpenShell separately with real credentials and networking.
10. Before a production release, supply resource profiles, backups and restoration
    drill, supported Dify upgrade paths, image digests, and a measured support matrix.