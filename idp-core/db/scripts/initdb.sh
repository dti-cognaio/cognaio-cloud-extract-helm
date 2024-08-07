#!/bin/bash
DB_SERVER=$PGHOST
DB_NAME=$PGDBNAME
DB_USER=$PGUSER
DB_PASSWORD=$PGPASSWORD

set -e

cp /scripts/05_cognaio_design.schema.sql /tmp/05_cognaio_design.schema.sql
cp /scripts/04_cognaio_extensions.schema.sql /tmp/04_cognaio_extensions.schema.sql
cp /scripts/06_cognaio_audits.schema.sql /tmp/06_cognaio_audits.schema.sql
cp /scripts/07_cognaio_repositories.schema.sql /tmp/07_cognaio_repositories.schema.sql

echo "START: Find and replace variables in sql scripts with environment variables"
sed -i "s|__COGNAIO_ENV_NAMESPACE__|"$NAMESPACE"|g" /tmp/05_cognaio_design.schema.sql
sed -i "s|__COGNAIO_ENV_ORGANIZATION_USERS__|"$ORGANIZATION_USERS"|g" /tmp/05_cognaio_design.schema.sql
sed -i "s|__COGNAIO_ENV_PGUSER__|"$PGUSER"|g" /tmp/05_cognaio_design.schema.sql
sed -i "s|__COGNAIO_ENV_APIKEY_AZUREOPENAI__|"$ApiKey_AzureOpenAi"|g" /tmp/05_cognaio_design.schema.sql
sed -i "s|__COGNAIO_ENV_ENDPOINT_AZUREOPENAI__|"$Endpoint_AzureOpenAi"|g" /tmp/05_cognaio_design.schema.sql
sed -i "s|__COGNAIO_ENV_APIKEY_NATIVEOPENAI__|"$ApiKey_NativeOpenAi"|g" /tmp/05_cognaio_design.schema.sql
sed -i "s|__COGNAIO_ENV_ENDPOINT_NATIVEOPENAI__|"$Endpoint_NativeOpenAi"|g" /tmp/05_cognaio_design.schema.sql
sed -i "s|__COGNAIO_ENV_APIKEY_AZUREAIDOCUMENTINTELLIGENCE__|"$ApiKey_AzureAiDocumentIntelligence"|g" /tmp/05_cognaio_design.schema.sql
sed -i "s|__COGNAIO_ENV_ENDPOINT_AZUREAIDOCUMENTINTELLIGENCE__|"$Endpoint_AzureAiDocumentIntelligence"|g" /tmp/05_cognaio_design.schema.sql
sed -i "s|__COGNAIO_ENV_APIKEY_AZURECOGNITIVESERVICESCOMPUTERVISION__|"$ApiKey_AzureCognitiveServicesComputervision"|g" /tmp/05_cognaio_design.schema.sql
sed -i "s|__COGNAIO_ENV_ENDPOINT_AZURECOGNITIVESERVICESCOMPUTERVISION__|"$Endpoint_AzureCognitiveServicesComputervision"|g" /tmp/05_cognaio_design.schema.sql
sed -i "s|__COGNAIO_ENV_PASSPHRASE_TEMPLATES__|"$PassPhrase_Templates"|g" /tmp/05_cognaio_design.schema.sql
sed -i "s|__COGNAIO_ENV_PGUSER__|"$PGUSER"|g" /tmp/04_cognaio_extensions.schema.sql
sed -i "s|__COGNAIO_ENV_PGUSER__|"$PGUSER"|g" /tmp/06_cognaio_audits.schema.sql
sed -i "s|__COGNAIO_ENV_PGUSER__|"$PGUSER"|g" /tmp/07_cognaio_repositories.schema.sql   
echo "END Find and replace variables in sql tmp with environment variables"

# Function to check if a PostgreSQL database exists
database_exists() {
    echo "Check if database exists: $1"
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_SERVER" -p "$PGPORT" -U "$DB_USER" -d postgres -c "SELECT datname FROM pg_database WHERE datname='$1'" | grep -q "$1"
}

# Function to check if a PostgreSQL schema exists in a given database
schema_exists() {
    echo "Check if schema exists: $2"
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_SERVER" -p "$PGPORT" -U "$DB_USER" -d "$1" -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name='$2'" | grep -q "$2"
}

# Connect to PostgreSQL server
psql -h "$DB_SERVER" -U "$DB_USER" -d postgres -c "\q"

# Create database if it does not exist
if ! database_exists "$DB_NAME"; then
    echo "Database does not exist, creating..."
    PGPASSWORD="$DB_PASSWORD" createdb -h "$DB_SERVER" -p "$PGPORT" -U "$DB_USER" "$DB_NAME"
fi

# Switch to the newly created database
echo "Switching to database: $DB_NAME"
psql -h "$DB_SERVER" -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" -c "\q"

# Create schema if it does not exist
if ! schema_exists "$DB_NAME" "cognaio_extensions"; then
    echo "Schema cognaio_extensions does not exist, creating..."
    psql -h "$DB_SERVER" -p "$PGPORT" -U $PGUSER -d "$DB_NAME" -a -f /tmp/04_cognaio_extensions.schema.sql; 
fi

# Create schema if it does not exist
if ! schema_exists "$DB_NAME" "cognaio_design"; then
    echo "Schema cognaio_design does not exist, creating..."
    psql -h "$DB_SERVER" -p "$PGPORT" -U $PGUSER -d "$DB_NAME" -a -f /tmp/05_cognaio_design.schema.sql;
fi

# Create schema if it does not exist
if ! schema_exists "$DB_NAME" "cognaio_audits"; then
    echo "Schema cognaio_audits does not exist, creating..."
    psql -h "$DB_SERVER" -p "$PGPORT" -U $PGUSER -d "$DB_NAME" -a -f /tmp/06_cognaio_audits.schema.sql;
fi

# Create schema if it does not exist
if ! schema_exists "$DB_NAME" "cognaio_repositories"; then
    echo "Schema cognaio_repositories does not exist, creating..."
    psql -h "$DB_SERVER" -p "$PGPORT" -U $PGUSER -d "$DB_NAME" -a -f /tmp/07_cognaio_repositories.schema.sql;
fi

echo "Database initialization complete."