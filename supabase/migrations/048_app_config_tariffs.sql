-- =============================================================================
-- 048 — Ajouter les tarifs Cloboto et Kloboto (3 offres de transport)
-- Dart : ride_tariff_service.dart
-- Dépend de : 003
-- =============================================================================
begin;

set local search_path to public, extensions;

insert into public.app_config (key, value_int, note) values
  ('ride_zemidjan_base_fcfa',        300,  'Zémidjan — prix de départ'),
  ('ride_zemidjan_per_km_fcfa',      150,  'Zémidjan — prix / km'),
  ('ride_cloboto_base_fcfa',         500,  'Cloboto — prix de départ'),
  ('ride_cloboto_per_km_fcfa',       200,  'Cloboto — prix / km'),
  ('ride_kloboto_base_fcfa',         700,  'Kloboto — prix de départ'),
  ('ride_kloboto_per_km_fcfa',       280,  'Kloboto — prix / km')
on conflict (key) do nothing;

commit;