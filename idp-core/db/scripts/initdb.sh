DB_SERVER=$PGHOST
DB_NAME=$PGDBNAME
DB_USER=$PGUSER
DB_PASSWORD=$PGPASSWORD

set -e

echo "DB_SERVER: $DB_SERVER"
echo "DB_NAME: $DB_NAME"
echo "DB_USER: $DB_USER"

# Function to check if a PostgreSQL database exists
database_exists() {
    echo "Check if database exists: $1"
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_SERVER" -U "$DB_USER" -d postgres -c "SELECT datname FROM pg_database WHERE datname='$1'" | grep -q "$1"
}

# Function to check if a PostgreSQL schema exists in a given database
schema_exists() {
    echo "Check if schema exists: $2"
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_SERVER" -U "$DB_USER" -d "$1" -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name='$2'" | grep -q "$2"
}

# Connect to PostgreSQL server
psql -h "$DB_SERVER" -U "$DB_USER" -d postgres -c "\q"

# Create database if it does not exist
if ! database_exists "$DB_NAME"; then
    echo "Database does not exist, creating..."
    PGPASSWORD="$DB_PASSWORD" createdb -h "$DB_SERVER" -U "$DB_USER" "$DB_NAME"
fi

# Switch to the newly created database
echo "Switching to database: $DB_NAME"
psql -h "$DB_SERVER" -U "$DB_USER" -d "$DB_NAME" -c "\q"

# Create schema if it does not exist
if ! schema_exists "$DB_NAME" "cognaio_extensions"; then
    echo "Schema cognaio_extensions does not exist, creating..."
    psql -h "$DB_SERVER" -U $PGUSER -d "$DB_NAME" -a -f /scripts/04_cognaio_extensions.schema.sql;
fi

# Create schema if it does not exist
if ! schema_exists "$DB_NAME" "cognaio_design"; then
    echo "Schema cognaio_design does not exist, creating..."
    psql -h "$DB_SERVER" -U $PGUSER -d "$DB_NAME" -a -f /scripts/05_cognaio_design.schema.sql;
fi

# Create schema if it does not exist
if ! schema_exists "$DB_NAME" "cognaio_audits"; then
    echo "Schema cognaio_audits does not exist, creating..."
    psql -h "$DB_SERVER" -U $PGUSER -d "$DB_NAME" -a -f /scripts/06_cognaio_audits.schema.sql;
fi

# Create schema if it does not exist
if ! schema_exists "$DB_NAME" "cognaio_repositories"; then
    echo "Schema cognaio_repositories does not exist, creating..."
    psql -h "$DB_SERVER" -U $PGUSER -d "$DB_NAME" -a -f /scripts/07_cognaio_repositories.schema.sql;
fi

echo "Database initialization complete."