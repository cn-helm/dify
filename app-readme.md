# Dify

Dify API, workflow workers, web console, collaboration, plugins, code execution,
and Agent local workspaces with integrated PostgreSQL, Redis, and Weaviate.

Prerequisites: a default StorageClass (or select one), a NetworkPolicy-capable CNI,
and access to the configured images. An Ingress controller and TLS Secret are
needed only for Ingress access. This chart does not install cluster infrastructure.

Start with Access and Storage. Internal connections and credentials are generated.
External dependencies and GitOps require an existing credentials Secret; see the
chart README. Default services are single-instance, not a highly available stack.

Runtime installation and Rancher UI testing are not yet certified. Template
validation alone does not verify image compatibility, CSI permissions, or isolation.