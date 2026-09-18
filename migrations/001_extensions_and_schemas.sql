BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE SCHEMA IF NOT EXISTS catalog;
CREATE SCHEMA IF NOT EXISTS api;
CREATE SCHEMA IF NOT EXISTS admin;
CREATE SCHEMA IF NOT EXISTS stage;
CREATE SCHEMA IF NOT EXISTS import;
CREATE SCHEMA IF NOT EXISTS account;

COMMENT ON SCHEMA catalog IS 'Normalized CBS RMT production data.';
COMMENT ON SCHEMA api IS 'Stable read/query contract for the API service.';
COMMENT ON SCHEMA admin IS 'Controlled mutation contract for administrative clients.';
COMMENT ON SCHEMA stage IS 'Raw JSON staging tables. Never queried by the public API.';
COMMENT ON SCHEMA import IS 'Validation and promotion routines for staged source data.';
COMMENT ON SCHEMA account IS 'Authenticated API user resources; OAuth token issuance remains outside PostgreSQL.';

COMMIT;
