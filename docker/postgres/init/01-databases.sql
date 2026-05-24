-- Executed automatically on first container startup
-- Each service uses its own isolated schema within the shared database

CREATE SCHEMA IF NOT EXISTS orders;
CREATE SCHEMA IF NOT EXISTS dashboard;
CREATE SCHEMA IF NOT EXISTS keycloak;

-- Dedicated user for Keycloak
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'keycloak_user') THEN
    CREATE ROLE keycloak_user WITH LOGIN PASSWORD 'change_me';
  END IF;
END
$$;

GRANT ALL PRIVILEGES ON SCHEMA keycloak TO keycloak_user;
