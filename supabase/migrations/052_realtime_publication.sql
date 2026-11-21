-- =============================================================================
-- 052 — Realtime : publier les tables critiques
-- Dart : tous les services qui écoutent (wallet, ride, mission, push...)
-- Dépend de : 050
-- =============================================================================
begin;

do $$
declare
  t text;
  tables text[] := array[
    'notifications','missions','mission_messages','mission_payments',
    'mission_reviews','rides','wallets','wallet_topup_requests',
    'providers','provider_reports','star_points_ledger'
  ];
begin
  foreach t in array tables loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null; when undefined_table then null;
    end;
  end loop;
end $$;

commit;