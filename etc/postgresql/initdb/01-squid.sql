\set ON_ERROR_STOP on
\getenv vector_password SQUID_VECTOR_PASSWORD
\getenv grafana_password SQUID_GRAFANA_PASSWORD

CREATE ROLE squid_vector LOGIN PASSWORD :'vector_password';
GRANT CONNECT ON DATABASE squid TO squid_vector;
GRANT USAGE ON SCHEMA public TO squid_vector;

CREATE TABLE public.squid_access_log (
    occurred_at     timestamptz NOT NULL,
    client_ip       inet,
    username        text,
    method          text,
    url             text,
    http_status     integer,
    squid_status    text,
    bytes_sent      bigint,
    duration_ms     bigint,
    hierarchy_type  text,
    upstream_ip     text,
    inserted_at     timestamptz NOT NULL
);

GRANT INSERT ON TABLE public.squid_access_log TO squid_vector;

CREATE ROLE squid_grafana LOGIN PASSWORD :'grafana_password';
GRANT CONNECT ON DATABASE squid TO squid_grafana;
GRANT USAGE ON SCHEMA public TO squid_grafana;
GRANT SELECT ON TABLE public.squid_access_log TO squid_grafana;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO squid_grafana;
