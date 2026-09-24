\set ON_ERROR_STOP on
\echo 'Installing CBS RMT PostgreSQL schema...'
\ir ../migrations/001_extensions_and_schemas.sql
\ir ../migrations/002_catalog_tables.sql
\ir ../migrations/003_relationship_tables.sql
\ir ../migrations/004_indexes.sql
\ir ../migrations/005_staging_tables.sql
\ir ../migrations/006_roles_and_grants.sql
\ir ../migrations/007_account_users.sql
\ir ../migrations/008_cast_correction_audit.sql
\ir ../migrations/009_cast_billing.sql
\ir ../functions/import/promote_json.sql
\ir ../functions/api/catalog.sql
\ir ../functions/admin/catalog.sql
\echo 'CBS RMT PostgreSQL schema installed.'
