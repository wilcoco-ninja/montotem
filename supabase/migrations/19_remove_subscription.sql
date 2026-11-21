-- =============================================================================
-- MONTOTEM : Script 19 - Suppression du système d'abonnement
-- Le modèle économique devient la commission sur chaque intervention.
-- Idempotent : peut être relancé sans risque.
-- =============================================================================

-- 0. Sauvegarde (une seule fois) des fonctions concernées
create table if not exists public._backup_functions_19 as
select p.proname::text as proname,
       pg_get_functiondef(p.oid) as def,
       now() as saved_at
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.prokind = 'f'
   and (p.prosrc ~* 'fin_abonnement' or p.proname ~* 'subscription');

alter table public._backup_functions_19 enable row level security;

create temp table if not exists tmp_patch_report (statut text, nom text);
truncate tmp_patch_report;

-- 1. Retrait des conditions "fin_abonnement > now()" dans les fonctions
do $$
declare
  r     record;
  v_new text;
begin
  for r in
    select p.oid, p.proname, pg_get_functiondef(p.oid) as def
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind = 'f'
       and p.prosrc ~* 'fin_abonnement\s*(>|>=)'
  loop
    v_new := r.def;

    -- (a) and (pv.fin_abonnement > now())
    v_new := regexp_replace(v_new,
      '\s+and\s+\(\s*([a-z_]+\.)?fin_abonnement\s*>=?\s*(now\(\)|current_timestamp)\s*\)',
      '', 'gi');
    -- (b) and pv.fin_abonnement > now()
    v_new := regexp_replace(v_new,
      '\s+and\s+([a-z_]+\.)?fin_abonnement\s*>=?\s*(now\(\)|current_timestamp)',
      '', 'gi');
    -- (c) pv.fin_abonnement > now() and ...   (condition en tête)
    v_new := regexp_replace(v_new,
      '([a-z_]+\.)?fin_abonnement\s*>=?\s*(now\(\)|current_timestamp)\s+and\s+',
      '', 'gi');
    -- (d) and pv.fin_abonnement is not null
    v_new := regexp_replace(v_new,
      '\s+and\s+([a-z_]+\.)?fin_abonnement\s+is\s+not\s+null',
      '', 'gi');

    if v_new = r.def then
      insert into tmp_patch_report values ('A CORRIGER A LA MAIN', r.proname::text);
      continue;
    end if;

    begin
      execute v_new;
      insert into tmp_patch_report values ('modifiee', r.proname::text);
    exception when others then
      insert into tmp_patch_report
      values ('ECHEC : ' || sqlerrm, r.proname::text);
    end;
  end loop;
end $$;

-- 2. Suppression des RPC de souscription
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('submit_subscription_request', 'admin_review_subscription')
  loop
    execute format('drop function %s', r.sig);
    insert into tmp_patch_report values ('fonction supprimee', r.sig::text);
  end loop;
end $$;

-- 3. Contrôle : il ne doit rester aucune dépendance à fin_abonnement
insert into tmp_patch_report (statut, nom)
select 'A VERIFIER : fonction', p.proname::text
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.prokind = 'f'
   and (p.prosrc ~* 'fin_abonnement\s*(>|>=|<|<=)'
        or p.prosrc ~* 'fin_abonnement\s+is\s+not\s+null')
union all
select 'A VERIFIER : politique RLS', pol.policyname::text
  from pg_policies pol
 where pol.schemaname = 'public'
   and (pol.qual ~* 'fin_abonnement' or pol.with_check ~* 'fin_abonnement')
union all
select 'A VERIFIER : vue', v.viewname::text
  from pg_views v
 where v.schemaname = 'public'
   and v.definition ~* 'fin_abonnement';

select statut, nom from tmp_patch_report order by statut, nom;