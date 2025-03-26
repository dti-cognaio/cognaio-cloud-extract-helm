# Change Log

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