# Change Log
## Version 3.1.0
### Changes
- New service `pageidentityservice` (Page Identity, image `dti/idp/cognaiopageidentity`, port 18080, schema `cognaio_page_identity`): values block, `deployment.yaml`, `service.yaml` and `secrets.yaml` (postgreSqlUser / postgreSqlPwd / pageIdentityAdminToken, controlled by `env.secret.init`). The existing suites (affinity, lifecycle, secrets) cover the service as well. Still open: nginx route (`/pageidentityservice`), the `BaseCognaioPageIdentityServiceUrl` / `Cognaio_PageIdentity_Admin_Token` wiring on `cognaioservice`, `hpa.yaml` / `serviceaccount.yaml`
- `cognaioservice` is now wired to `pageidentityservice`, which closes the gap left open when the service was added: `BaseCognaioPageIdentityServiceUrl` (the fallback in the image points at an nginx route this chart does not render), `Cognaio_PageIdentity_Admin_Token` read from the `pageidentityservice` secret so there is no second copy to keep in sync, plus `Cognaio_PageIdentity_Deployment_Mode` and the optional `Cognaio_PageIdentity_Initial_Retention_Months`. Without the token every `/admin/tenants/*` call - including the auto-registration at startup - fails closed with `503`
- The complete feature catalogue is now configurable, with the defaults the image ships with. Newly exposed: `vodafoneAiBoosterDisabled`, `reportingPageIdentityDisabled`, `reportingEmptyPagesDisabled`, plus the three login-screen toggles under `cognaioservice.env.ui` (`Cognaio_UI_Login_*`). `Cognaio_Feature_Mailboxes_Manage_Disabled` is deliberately left out - the flag is on its way out of the image
- The shipped defaults follow the image config, with four deliberate exceptions kept at their existing chart value so no values file has to change on upgrade: `cerebralEdgeDisabled`, `llmTemplatesSyncDisabled`, `endpointsManageDisabled` and `viewPlatformAuditsDisabled` stay `false`. A test guards every default against drift
- New service `cryptoprovider` (cognaio-crypto, image `dti/idp/cryptoprovider`, port 3000): the one holder of the platform main key. `cognaioservice`, `cognaioflexsearchservice` and the SchemaManager send it a locked data key and get the usable one back; it sees no documents, no customer data and no database. `deployment.yaml`, `service.yaml`, `secrets.yaml`, `hpa.yaml`, `serviceaccount.yaml` and the first `networkpolicy.yaml` in this chart
- All five KEK custodies are templated (`cryptoprovider.env.kek.provider`: `azurekv` | `awskms` | `gcpkms` | `keyfile` | `env`), default `azurekv` with vault access through its own service account (Workload Identity / IRSA), so no vault credential has to sit in a secret. Every configured custody renders, not only the selected one - a custody switch deliberately keeps the outgoing one as read side while the sweep re-wraps
- `cryptoprovider.env.kek.requireRealPepper` maps `Crypto_Require_Real_Pepper`: without it a deployment whose `kek.pepperB64` is unset silently binds the effective key to `DEV_PEPPER`, a constant that is public in the source. With it, a missing pepper is a boot failure. Note that the kid records the pepper *version* (`+p1`), not its content - setting a pepper on an environment that already holds data is a key rotation, not a configuration tweak
- `cryptoprovider` is reachable inside the cluster only: no nginx upstream, no ingress route, no published port. mTLS on the caller-to-crypto hop is expected from the service mesh (Istio), so the callers get an `http://` URL; the image can serve TLS itself, but the chart does not template it
- `NetworkPolicy` (`cryptoprovider.networkPolicy.enabled`, default `true`) restricts the crypto port to `cognaioservice`, `cognaioflexsearchservice` and the SchemaManager Job. `networkPolicy.extraIngress` is the escape hatch for a mesh telemetry path or a CNI that filters kubelet probes
- Readiness of `cryptoprovider` is `httpGet /readyz`, not a TCP check: `/readyz` runs a real wrap/unwrap against the configured main key, so a wrong vault key surfaces during the rollout instead of when someone opens a record. The blanket probe suite no longer demands `tcpSocket` on every readiness probe
- **`cognaioservice` and `cognaioflexsearchservice` hold no key material any more.** Every `PassPhrase_*` variable plus `Token_EncryptionToken_JwtKey`, `OpenID_PassPhrase_UserInfo` and `OpenID_PassPhrase_OidcSecrets` are gone from their pods (19 entries), and `PassPhrase_Repositories` is gone from flexsearch. Both get an address and a token instead: `Crypto_Service_Url` and `Crypto_Service_Token`. New suite `cognaioservice_no_passphrases_test.yaml` nails that down
- The values and secret keys stay: the SchemaManager seeds each of them once into the key table and validates them on **every** rollout, so a cleared entry fails the next deploy. `Token_*_ExpiresInMinutes` are lifetimes, not keys - they were never affected
- **Breaking:** the SchemaManager left the `cognaioservice` pod. `cognaioservice.init.*` is replaced by a top-level `cognaioschemamanager` block (`image`, `otel`, `securityContext`, `resources`, `extraEnv`, volume lists, `backoffLimit`, `ttlSecondsAfterFinished`, `gate`) and runs as its own Job. Everything else the migrator reads still comes from `cognaioservice.env.*` and the `cognaioservice` secret
- The SchemaManager Job waits for `http://cryptoprovider/readyz` in an init container before the migrator starts, and that wait is not optional. The migrator pings the crypto provider at startup and throws when it is unreachable, but the exception escapes `ExecuteAsync`, the generic host catches it with `BackgroundServiceExceptionBehavior=StopHost`, and the process ends with **exit code 0** - the Job counts as succeeded, never retries, and the migration silently never runs. Waiting removes the failure mode entirely; `/readyz` is registered before the bearer middleware, so it needs no token, and it is a real wrap/unwrap against the configured main key
- The gate init container on the database services no longer waits mutely: it acts on every answer the Kubernetes API gives, fails fast with a named cause on `403` (a permission problem never resolves itself), prints network errors, and logs the last API answer every 60s. A gate that cannot tell "not finished yet" from "not allowed to ask" is indistinguishable from a slow migration
- The rollout order is now enforced: `cryptoprovider` ready -> SchemaManager Job exits 0 -> the four database services start. The Job fails loud and retries while the crypto provider is still coming up (`backoffLimit`, default 30); each database service gets a `wait-for-schema-manager` init container that polls the Job through the Kubernetes API, so a failed migration never becomes a running service. `cognaioschemamanager.gate.enabled: false` is the RBAC-free fallback (services CrashLoopBackOff until the migration is through)
- New `Role` + `RoleBinding` granting `get` on `batch/jobs` to the service accounts the four gated deployments already use - no new identity is minted, so Workload Identity annotations on those accounts stay untouched
- A finished Job is immutable, so it has to be recreated or the migration silently does not run on the next rollout - the gate would read `succeeded` from the previous release and wave the services through. Two supported ways: `cognaioschemamanager.jobNamePerRevision: true` (the default) puts the release revision in the name, which makes plain `helm upgrade` correct on its own at the cost of the four gated services rolling along every upgrade; `false` keeps a stable name and leaves the recreation to the delivery tool
- New `cognaioschemamanager.annotations` and `cryptoprovider.annotations` passthroughs plus `examples/values-argocd.yaml`: an ArgoCD `Sync` hook with `hook-delete-policy: BeforeHookCreation` recreates the Job under a stable name, and sync waves `-2` (crypto provider) / `-1` (Job) / `0` (rest) order the rollout natively - the same pattern the `azure-akv-secrets-syncer` Job already uses. Nothing else rolls per sync, and `kubectl logs job/cognaioschemamanager` works without a revision number
- `cognaioschemamanager.ttlSecondsAfterFinished` is **empty** by default. The gate polls the Job by name, so it has to outlive the rollout: a pod restarting later (node drain, eviction, OOM, scale-up) polls a TTL-collected Job, gets a `404` and would wait in `Init` forever. Helm removes the previous revision's Job on upgrade anyway, and `BeforeHookCreation` does the same
- Four new custody feature flags under `cognaioservice.env.feature`, all `true` (= not offered) by default: `custodyByokDisabled`, `custodyHyokDisabled`, `dataReencryptionDisabled`, `orgCustodySelfServiceDisabled`. Platform-managed keys are always available and cannot be switched off
- New example overlay `examples/values-crypto-azurekv.yaml`, plus a `Crypto Provider (KEK Custody)` and a `Rollout Order` section in the ReadMe. `values-azure-auth.yaml`, `values-security.yaml` and the two resource overlays follow the `cognaioservice.init` -> `cognaioschemamanager` move
- **Breaking:** this release pairs the chart with 3.1.0 images. The crypto provider is mandatory - `cognaioservice`, `cognaioflexsearchservice` and the SchemaManager all fail loud at startup without it - and a 3.0.x image would no longer receive the passphrases it still reads
- Before the first rollout: create the vault key and grant it to the crypto provider identity, then generate `cryptoprovider.env.cryptoVoucherKeyB64` and **back it up immediately**. A lost voucher key makes the data of every organization with its own key permanently unreadable - there is no recovery path. Old key versions in the vault must stay enabled, and the `cognaio_extensions` schema belongs in every backup from the same run as the data
- New global `otel` block in values.yaml: OpenTelemetry (traces, metrics and logs via OTLP) can be switched on for all instrumented services from one place - `otel.enabled: true` plus the two OTLP endpoints. `enabled`, `serviceName`, `endpoint` and `captureHeaders` can be overridden per service under `<service>.otel`
- Instrumented services: `cognaioservice`, `cognaioflexsearchservice`, `emailservice`, `cognaioauditscleanup`, `imageprovider`, `objectdetectionprovider`, `pageidentityservice` and the `cognaioschemamanager` init container. `nginx`, `redis`, `cognaioinsightagentic` and `usermanual` are unchanged
- Two endpoints, because the protocols differ: `otel.endpointGrpc` (`:4317`) is used for the .NET containers, `otel.endpoint` (`:4318`) for the Node / Python services. Both are required - there is deliberately no default hostname, since a wrong one would export into the void without any visible error
- `otel.captureHeaders` (default `x-tenant`) is an allowlist of incoming headers that are copied onto the server span; `otel.resourceAttributes` stamps all three signals of the installation (e.g. `deployment.environment`); `otel.extraEnv` passes anything else the SDKs read from the environment (sampling, `OTEL_LOG_LEVEL`)
- **Not a breaking change:** OpenTelemetry is off by default. With `otel.enabled: false` the rendered manifests are identical to the previous version - no `OTEL_*` variables
- New example overlay `examples/values-otel.yaml` and a new `OpenTelemetry (Observability)` section in the ReadMe

### Versions
|Repository|Version|
|---|---|
|dtideregistry.azurecr.io/dti/idp/cognaioinsight-agentic     |3.1.0|
|dtideregistry.azurecr.io/dti/idp/cognaioservice             |3.1.0|
|dtideregistry.azurecr.io/dti/idp/image                      |3.1.0|
|dtideregistry.azurecr.io/dti/idp/emailservice               |3.1.0|
|dtideregistry.azurecr.io/dti/idp/cognaioflexsearchservice   |3.1.0|
|dtideregistry.azurecr.io/dti/idp/cognaioauditscleanup       |3.1.0|
|dtideregistry.azurecr.io/dti/idp/objectdetectionprovider    |3.1.0|
|dtideregistry.azurecr.io/dti/idp/cognaioschemamanager       |3.1.0|
|dtideregistry.azurecr.io/dti/idp/cce-user-manual            |3.1.0|
|dtideregistry.azurecr.io/dti/idp/pageidentityservice        |3.1.0|
|dtideregistry.azurecr.io/dti/idp/cryptoprovider             |3.1.0|
|dtideregistry.azurecr.io/nginx/nginx                        |1.31.4-alpine-slim|
|dtideregistry.azurecr.io/redis/redis                        |8.10.1-alpine|
---

## Version 3.0.1
### Changes
- Updates to third-party dependencies for all of the services
- Used up to date base images for each service
- Small bug fixes and minor user experience improvements

### Versions
|Repository|Version|
|---|---|
|dtideregistry.azurecr.io/dti/idp/cognaioinsight-agentic     |3.0.1|
|dtideregistry.azurecr.io/dti/idp/cognaioservice             |3.0.1|
|dtideregistry.azurecr.io/dti/idp/image                      |3.0.1|
|dtideregistry.azurecr.io/dti/idp/emailservice               |3.0.1|
|dtideregistry.azurecr.io/dti/idp/cognaioflexsearchservice   |3.0.1|
|dtideregistry.azurecr.io/dti/idp/cognaioauditscleanup       |3.0.1|
|dtideregistry.azurecr.io/dti/idp/objectdetectionprovider    |3.0.1|
|dtideregistry.azurecr.io/dti/idp/cognaioschemamanager       |3.0.1|
|dtideregistry.azurecr.io/dti/idp/cce-user-manual            |3.0.1|
|dtideregistry.azurecr.io/nginx/nginx                        |1.31.2-alpine-slim|
|dtideregistry.azurecr.io/redis/redis                        |8.8.0-alpine|
---

## Version 3.0.0
### Changes
- cognaioinsight-agentic is now the main UI, served at `/cognaioinsight`
- Removed legacy cognaioinsight service (configmap, deployment, HPA, service, serviceaccount)
- `/cognaioinsight-agentic` is 301-redirected to `/cognaioinsight`
- Root path (`/`) now 301-redirects directly to `/cognaioinsight/`; unmatched paths return 404 instead of redirecting to the external URL
- New OIDC authentication stack for group / role / claims mapping: org-scoped providers, group-to-role mappings and service-token grants. **Developed and tested exclusively against Microsoft Entra ID — Entra ID is currently the only validated and supported provider.** The stack is implemented provider-generically, so other OIDC providers (Google, GitHub, Okta, Keycloak, AWS Cognito, generic OIDC) can technically be configured but are **not yet validated or supported**. Existing authentication, including the built-in COGNAiO email OTP and the Microsoft / Google / GitHub login providers, continues to work as in previous versions
- New platform-level audit log; admin layer can browse and export audit artifacts via the agentic UI
- **Breaking:** renamed `cognaioservice.env.featurePreview` to `cognaioservice.env.feature` in values.yaml — update your values file accordingly
- **Breaking:** moved `cognaioservice.env.endpointsManageDisabled` into the `cognaioservice.env.feature` block
- **Breaking:** removed `cognaioservice.env.featurePreview.uiAiChainCrafterDisabled` (feature is now generally available)
- **Breaking:** new mandatory passphrase `cognaioservice.env.openID.passPhraseOidcSecrets` — used to encrypt OIDC client secrets in the database. Must be set before upgrade or the `cognaio_design` schema migration will fail with `pgcrypto` error `39000: Illegal argument to function`
- New feature flags under `cognaioservice.env.feature`: `appKeyUsageDisabled`, `pageRetentionDisabled`, `llmTemplatesSyncDisabled`, `viewPlatformAuditsDisabled`
- Added `<service>.extraContainers` extension point on every deployment, allowing customers to inject sidecar containers (e.g., authentication proxy) without modifying the chart
- `cognaioservice.env.organization.users` entries are now plain emails — the legacy inner single-quote wrapping (`"'email@example.com'"`) is no longer required

### Versions
|Repository|Version|
|---|---|
| ~~dtideregistry.azurecr.io/dti/idp/cognaioinsight~~        |2.6.0|
|dtideregistry.azurecr.io/dti/idp/cognaioinsight-agentic     |3.0.0|
|dtideregistry.azurecr.io/dti/idp/cognaioservice             |3.0.0|
|dtideregistry.azurecr.io/dti/idp/image                      |3.0.0|
|dtideregistry.azurecr.io/dti/idp/emailservice               |3.0.0|
|dtideregistry.azurecr.io/dti/idp/cognaioflexsearchservice   |3.0.0|
|dtideregistry.azurecr.io/dti/idp/cognaioauditscleanup       |3.0.0|
|dtideregistry.azurecr.io/dti/idp/objectdetectionprovider    |3.0.0|
|dtideregistry.azurecr.io/dti/idp/cognaioschemamanager       |3.0.0|
|dtideregistry.azurecr.io/dti/idp/cce-user-manual            |3.0.0|
|dtideregistry.azurecr.io/nginx/nginx                        |1.31.1-alpine-slim|
|dtideregistry.azurecr.io/redis/redis                        |8.8.0-alpine|
---

## Version 2.6.0
### Changes
- New UI cognaioinsight-agentic
- Removed cognaiostudio (/cognaioanalyze)
- Updated to Helm v4
- Restructure HelmCharts
- Add Helm best practices
- Add Helm unittest
- Added configurable `restartPolicy` per service with global default fallback
- Added configurable `lifecycle` hooks (e.g., preStop) per service for graceful shutdown

### Versions
|Repository|Version|
|---|---|
| ~~dtideregistry.azurecr.io/dti/idp/cognaiostudio~~         |2.5.1|
|dtideregistry.azurecr.io/dti/idp/cognaioinsight             |2.6.0|
|dtideregistry.azurecr.io/dti/idp/cognaioinsight             |2.6.0-Agentic-Preview *|
|dtideregistry.azurecr.io/dti/idp/cognaioservice             |2.6.0|
|dtideregistry.azurecr.io/dti/idp/image                      |2.6.0|
|dtideregistry.azurecr.io/dti/idp/emailservice               |2.6.0|
|dtideregistry.azurecr.io/dti/idp/cognaioflexsearchservice   |2.6.0|
|dtideregistry.azurecr.io/dti/idp/cognaioauditscleanup       |2.6.0|
|dtideregistry.azurecr.io/dti/idp/objectdetectionprovider    |2.6.0|
|dtideregistry.azurecr.io/dti/idp/cognaioschemamanager       |2.6.0|
|dtideregistry.azurecr.io/dti/idp/cce-user-manual            |2.6.0|
|dtideregistry.azurecr.io/nginx/nginx                        |1.29.5-alpine-slim|
|dtideregistry.azurecr.io/redis/redis                        |8.6.1-alpine|
>\* = Added
---

## Version 2.5.2
### Changes
- Added connector for AiBooster support
- Added cognaioauditscleanup service
- Updated used libraries and dependencies in images

### Versions
|Repository|Version|
|---|---|
|dtideregistry.azurecr.io/dti/idp/cognaiostudio              |2.5.1|
|dtideregistry.azurecr.io/dti/idp/cognaioinsight             |2.5.1-Insight-Preview|
|dtideregistry.azurecr.io/dti/idp/cognaioservice             |2.5.1|
|dtideregistry.azurecr.io/dti/idp/image                      |2.5.1|
|dtideregistry.azurecr.io/dti/idp/emailservice               |2.5.1|
|dtideregistry.azurecr.io/dti/idp/cognaioflexsearchservice   |2.5.1|
|dtideregistry.azurecr.io/dti/idp/cognaioauditscleanup       |2.5.1 *|
|dtideregistry.azurecr.io/dti/idp/objectdetectionprovider    |2.5.1|
|dtideregistry.azurecr.io/dti/idp/cognaioschemamanager       |2.5.1|
|dtideregistry.azurecr.io/dti/idp/cce-user-manual            |2.5.1|
|dtideregistry.azurecr.io/nginx/nginx                        |1.29.3-alpine-slim|
|dtideregistry.azurecr.io/redis/redis                        |8.2.3-alpine|
>\* = Added
---

## Version 2.5.1
### Changes
- Added volumes and volumemounts to cognaioservice and cognaioflexsearchservice

## Version 2.5.0
### Changes
- Added preview version of Cognaio Insight UI
- Added SSL Required flag to Cognaio Schema Manager
- Added Azure AI Foundry resource settings
- Introduced possibility of OpenID authentication
- Added settings for Endpoints encryption, required for possibility to edit them
- Added minor adjustments to NGINX config for better load balancing

### Versions
|Repository|Version|
|---|---|
|dtideregistry.azurecr.io/dti/idp/cognaiostudio              |2.5.0|
|dtideregistry.azurecr.io/dti/idp/cognaioinsight             |2.5.0-Insight-Preview *|
|dtideregistry.azurecr.io/dti/idp/cognaioservice             |2.5.0|
|dtideregistry.azurecr.io/dti/idp/image                      |2.5.0|
|dtideregistry.azurecr.io/dti/idp/emailservice               |2.5.0|
|dtideregistry.azurecr.io/dti/idp/cognaioflexsearchservice   |2.5.0|
|dtideregistry.azurecr.io/dti/idp/objectdetectionprovider    |2.5.0|
|dtideregistry.azurecr.io/dti/idp/cognaioschemamanager       |2.5.0|
|dtideregistry.azurecr.io/dti/idp/cce-user-manual            |2.5.0|
|dtideregistry.azurecr.io/nginx/nginx                        |1.29.0-alpine-slim|
|dtideregistry.azurecr.io/redis/redis                        |8.2.0-alpine|
>\* = Added
---

## Version 2.4.0
### Changes
- Added settings allowing to use AWS services
- Introduced new LLM settings to COGNAiO Service
- Introduced User Manual service
- Added required Redis service
- Extended mailbox connectivity settings in case it's required
- Added Base URLs for services to COGNAiO Service configuration
- Added nginx config map to COGNAiO Studio

### Versions
|Repository|Version|
|---|---|
|dtideregistry.azurecr.io/dti/idp/cognaiostudio              |2.4.0|
|dtideregistry.azurecr.io/dti/idp/cognaioservice             |2.4.0|
|dtideregistry.azurecr.io/dti/idp/image                      |2.4.0|
|dtideregistry.azurecr.io/dti/idp/emailservice               |2.4.0|
|dtideregistry.azurecr.io/dti/idp/cognaioflexsearchservice   |2.4.0|
|dtideregistry.azurecr.io/dti/idp/objectdetectionprovider    |2.4.0|
|dtideregistry.azurecr.io/dti/idp/cognaioschemamanager       |2.4.0|
|dtideregistry.azurecr.io/dti/idp/cce-user-manual            |2.4.0 *|
|dtideregistry.azurecr.io/nginx/nginx                        |1.27.4|
|dtideregistry.azurecr.io/bitnami/redis                      |7.4.2 *|
>\* = Added
---

## Version 2.3.0
### Changes
- UI enhancements
- Ability of analyzing multiple documents
- Ability to separate documents inside a batch
- Support of new AI models like gpt-4o and gpt-4o-mini
- Add italian and spanish to ui
- New initialization of database
- Replaced cognaioapp with cognaiostudio
- Upgrade nginx

|Repository|Version|
|---|---|
|dtideregistry.azurecr.io/dti/idp/cognaiostudio              |2.3.0 *|
|dtideregistry.azurecr.io/dti/idp/cognaioservice             |2.3.0|
|dtideregistry.azurecr.io/dti/idp/image                      |2.3.0|
|dtideregistry.azurecr.io/dti/idp/emailservice               |2.3.0|
|dtideregistry.azurecr.io/dti/idp/cognaioflexsearchservice   |2.3.0|
|dtideregistry.azurecr.io/dti/idp/objectdetectionprovider    |2.3.0|
|dtideregistry.azurecr.io/nginx/nginx                        |1.27.1|
>\* = Replaced/Renamed of cognaioapp

## Version 2.2.1
### Changes
- Possibility to disable deployment of ingress
- All deployments have now the possibility to add resource definitions
- Adjust SQL-Scripts to use environment variables. Fixed hardcoded secrets in values file.
- Change some default values for database (name, ssl required)
- Change structure to provide organization.users e-mail address
- Make PostgreSQL port configurable, remove sqlserver from secrets

## Version 2.2.0
### Changes
- Enhanced designer options
- Ability of object detection
- Ability to support multiple UI Themes dynamically inside Cognaio UI
- API Endpoint to manage projects
- Ability to create multiple app keys of a certain plan
- Upgrade nginx

### Versions
|Repository|Version|
|---|---|
|dtideregistry.azurecr.io/dti/idp/cognaioapp                 |2.2.0|
|dtideregistry.azurecr.io/dti/idp/cognaioservice             |2.2.0|
|dtideregistry.azurecr.io/dti/idp/image                      |2.2.0|
|dtideregistry.azurecr.io/dti/idp/emailservice               |2.2.0|
|dtideregistry.azurecr.io/dti/idp/cognaioflexsearchservice   |2.2.0|
|dtideregistry.azurecr.io/dti/idp/objectdetectionprovider    |2.2.0 *|
|dtideregistry.azurecr.io/nginx/nginx                        |1.25.4|
>\* = Added
---

## Version 2.1.1
### Changes
- Fixes for Email Service regarding PDF files MIME types

### Versions
|Repository|Version|
|---|---|
|dtideregistry.azurecr.io/dti/idp/emailservice               |2.1.1|
---

## Version 2.1.0 (Azure Deployment)
### Changes
- Increase timeouts application gateway
- Rename databases

### Versions
|Repository|Version|
|---|---|
|dtideregistry.azurecr.io/dti/idp/cognaioapp                 |2.1.0|
|dtideregistry.azurecr.io/dti/idp/cognaioservice             |2.1.0|
|dtideregistry.azurecr.io/dti/idp/image                      |2.1.0|
|dtideregistry.azurecr.io/dti/idp/emailservice               |2.1.0|
|dtideregistry.azurecr.io/dti/idp/cognaioflexsearchservice   |2.1.0|
---
## Version 2.0.2 (Azure Deployment) Datacenter Move Hotfix
### Changes
- If the content filter of openai takes effect, the request is sent as a fallback to the document intelligent service

### Versions
|Repository|Version|
|---|---|
dtideregistry.azurecr.io/dti/idp/cognaioservice             |2.0.2|
---
## Version 2.0.1 (Azure Deployment) Datacenter Move Hotfix
### Changes
- Raise proper error message on client side when OpenAI restricts some content (Hate, Sexual etc)
- Catch new type of content filter error sent back by OpenAI service

### Versions
|Repository|Version|
|---|---|
dtideregistry.azurecr.io/dti/idp/cognaioservice             |2.0.1|
---
## Version 2.0.0 (Azure Deployment) Datacenter Move
### Changes
- Add email service
- Add flexsearch service
- Database encryption
- Automatic database inizialisation through cognaioservice

### Versions
|Repository|Version|
|---|---|
|dtideregistry.azurecr.io/dti/idp/cognaioapp                 |2.0.0|
|dtideregistry.azurecr.io/dti/idp/cognaioservice             |2.0.0|
|dtideregistry.azurecr.io/dti/idp/image                      |2.0.0|
|dtideregistry.azurecr.io/dti/idp/emailservice               |2.0.0 *|
|dtideregistry.azurecr.io/dti/idp/cognaioflexsearchservice   |2.0.0 *|
|dtideregistry.azurecr.io/dti/idp/postgresql-helper          |1.0.0 *|
>\* = Added

---
## Version 1.0.0 (Azure Deployment)

|Repository|Version|
|---|---|
|dtideregistry.azurecr.io/nginx/nginx                        |1.24.0|
|dtideregistry.azurecr.io/dti/idp/cognaioapp                 |1.0.0|
|dtideregistry.azurecr.io/dti/idp/cognaioservice             |1.0.0|
|dtideregistry.azurecr.io/dti/idp/image                      |1.0.0|
|dtideregistry.azurecr.io/skilja/extractionservice           |3.5|