# Change Log
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