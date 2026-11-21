-- =============================================================================
-- 001 — Extensions PostgreSQL
-- Dart : (aucun)
-- Dépend de : rien
-- =============================================================================
begin;

create extension if not exists postgis with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net;
create extension if not exists pgcrypto;

commit;