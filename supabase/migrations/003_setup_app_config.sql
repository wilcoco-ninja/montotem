-- =============================================================================
-- 003 — Configuration plateforme (tarifs courses uniquement)
-- Dart : ride_tariff_service.dart (lit ride_*_fcfa), wallet_service.dart
--        (lit wallet_block_threshold_fcfa)
-- Dépend de : 002
-- IMPORTANT : les commissions sont dans commission_rules (019), PAS ici.
-- =============================================================================
begin;

create table if not exists public.app_config (
  key        text primary key,
  value_int  integer,
  value_json jsonb,
  note       text,
  updated_at timestamptz not null default now()
);

insert into public.app_config (key, value_int, note) values
  ('wallet_block_threshold_fcfa',  2000, 'Blocage si solde < -seuil (FCFA)'),
  ('ride_zemidjan_base_fcfa',       300, 'Zémidjan — prix de départ'),
  ('ride_zemidjan_per_km_fcfa',     150, 'Zémidjan — prix / km'),
  ('ride_tricycle_base_fcfa',      1500, 'Tricycle — prix de départ'),
  ('ride_tricycle_per_km_fcfa',     400, 'Tricycle — prix / km')
on conflict (key) do nothing;

commit;