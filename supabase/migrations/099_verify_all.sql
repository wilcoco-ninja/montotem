-- =============================================================================
-- 099 — Vérification exhaustive
-- À exécuter en dernier. Ne modifie rien.
-- =============================================================================
begin;

-- A. Tables attendues (attendu : 24)
do $$
declare
  v_ok int := 0; v_total int := 0; v_missing text := '';
  t text;
  tables text[] := array[
    'profiles','admin_roles','notifications','app_config','payment_settings',
    'emergency_numbers','providers','provider_skills','provider_catalog_items',
    'wallets','wallet_transactions','wallet_topup_requests',
    'missions','mission_items','mission_events','mission_payments',
    'mission_messages','mission_reviews','star_points_ledger',
    'rides','provider_reports','commission_rules','vehicles','maintenance_rules'
  ];
begin
  foreach t in array tables loop
    v_total := v_total + 1;
    if to_regclass('public.'||t) is not null then v_ok := v_ok + 1;
    else v_missing := v_missing || E'\n  - ' || t; end if;
  end loop;
  raise notice '== TABLES : % / % ==', v_ok, v_total;
  if v_missing <> '' then raise warning 'Manquantes : %', v_missing; end if;
end $$;

-- B. RPC attendues (attendu : ~50)
do $$
declare
  v_ok int := 0; v_total int := 0; v_missing text := '';
  r text;
  rpcs text[] := array[
    'is_admin()','is_super_admin()','haversine_km(double precision,double precision,double precision,double precision)',
    'safe_notify(uuid,text,text,text,jsonb)','safe_notify_admins(text,text,text,jsonb)',
    'register_profile(text,text,text,text,text,text,text,text,text,text,text,double precision,double precision)',
    'provider_public_catalog(uuid)','set_provider_catalog(text[],jsonb,integer,integer,integer,text)',
    'add_provider_skill(text)','remove_provider_skill(uuid)',
    'submit_provider_identity(text,text,text,text,text,text,text,jsonb)',
    'set_provider_momo(text,text,text)',
    'create_mission(uuid,text,uuid[],double precision,double precision,text,text)',
    'mission_provider_action(uuid,text)','my_missions()','mission_to_json(uuid)',
    'update_provider_position(uuid,double precision,double precision)',
    'cancel_mission(uuid,text)','send_mission_message(uuid,text)',
    'submit_review(uuid,integer,text)','submit_provider_report(uuid,uuid,text,text)',
    'reject_mission_payment(uuid,text)',
    'declare_mission_payment(uuid,text,text,text,text)','confirm_mission_payment(uuid)',
    'apply_travel_commission(uuid,integer,uuid)','check_wallet_block(uuid)',
    'create_ride(text,double precision,double precision,double precision,double precision,integer,text,text,text)',
    'ride_action(uuid,text,integer,text)','ride_details(uuid)','my_rides()',
    'update_ride_provider_position(uuid,double precision,double precision)',
    'rides_nearby(double precision,double precision,numeric)',
    'update_driver_location(double precision,double precision)',
    'admin_dashboard_stats()','admin_finance_summary(integer)',
    'admin_revenue_summary(integer)','admin_set_provider_status(uuid,text,text)',
    'admin_resolve_report(uuid,text,text,boolean)',
    'admin_rides(integer)','admin_cancel_ride(uuid,text)',
    'admin_credit_wallet(uuid,integer,text,text)',
    'admin_review_wallet_topup(uuid,boolean,text)',
    'submit_wallet_topup(integer,text,text,text)',
    'admin_list_commission_rules()',
    'admin_upsert_commission_rule(uuid,text,text,text,numeric,boolean,text)',
    'admin_delete_commission_rule(uuid)','admin_commission_summary()',
    'provider_earnings_summary(integer)',
    'providers_nearest(double precision,double precision,text,text,numeric,integer)',
    'providers_in_bounds(double precision,double precision,double precision,double precision,integer)',
    'provider_vehicle_map()','get_emergency_numbers()',
    'expire_unpaid_missions(integer)','purge_old_notifications()',
    'commission_pct(text,text,text)'
  ];
begin
  foreach r in array rpcs loop
    v_total := v_total + 1;
    if to_regprocedure('public.'||r) is not null then v_ok := v_ok + 1;
    else v_missing := v_missing || E'\n  - ' || r; end if;
  end loop;
  raise notice '== FONCTIONS : % / % ==', v_ok, v_total;
  if v_missing <> '' then raise warning 'Manquantes : %', v_missing; end if;
end $$;

-- C. Realtime (attendu : 11 tables)
select count(*) as tables_realtime
  from pg_publication_tables
 where pubname = 'supabase_realtime' and schemaname = 'public';

-- D. Jobs cron (attendu : 2)
select count(*) as jobs_actifs
  from cron.job where jobname like 'montotem_%' and active;

-- E. Config
select key, value_int from public.app_config order by key;

-- F. Commissions par défaut (attendu : 9 règles)
select count(*) as commission_rules_count
  from public.commission_rules where actif;

-- Vérifier que commission_pct retourne les bonnes valeurs
select
  public.commission_pct('ride_zemidjan','zemidjan',null) as zemidjan_pct,          -- 15
  public.commission_pct('ride_tricycle_passenger','tricycle_passenger',null) as pass_pct, -- 12
  public.commission_pct('ride_tricycle_fret','tricycle_fret',null) as fret_pct,    -- 15
  public.commission_pct('mission_remorquage','garage',null) as rem_pct;            -- 8

-- G. Admin bootstrap
select p.id, p.email, p.role, ar.level
  from public.profiles p
  left join public.admin_roles ar on ar.user_id = p.id
 where p.role = 'admin';

-- H. Vue d'ensemble
select
  (select count(*) from pg_tables where schemaname = 'public') as tables,
  (select count(*) from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public') as fonctions,
  (select count(*) from pg_policies where schemaname = 'public') as policies,
  (select count(*) from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public') as tables_realtime;

commit;