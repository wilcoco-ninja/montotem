-- =============================================================================
-- 056 — Nettoyage définitif du système d'abonnement
-- Modèle : COMMISSION uniquement (Uber Eats / Gozem)
-- Idempotent.
-- =============================================================================
begin;
set local search_path to public, extensions;

drop function if exists public.admin_review_subscription(uuid, boolean, text);
drop function if exists public.request_provider_subscription(text, integer, text, text);
drop function if exists public.submit_subscription_request(integer, text, text, text);
drop table if exists public.subscription_requests cascade;
alter table public.providers drop column if exists fin_abonnement;

delete from public.commission_rules
 where service_category like 'subscription%'
    or note ilike '%abonnement%'
    or note ilike '%subscription%';

commit;