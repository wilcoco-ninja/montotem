-- =============================================================================
-- MONTOTEM : Script 15 - Tarifs de départ des courses (valeurs provisoires)
-- Fichier  : sql/15_ride_tariffs.sql
-- Prérequis : scripts 01b à 14 exécutés. Idempotent (ne remplace jamais une
-- valeur déjà modifiée).
-- =============================================================================
begin;

insert into public.app_config (key, value_int, note) values
  ('ride_zemidjan_base_fcfa',  300,
   'Zémidjan : prix de départ (couvre le 1er km), FCFA. Valeur provisoire.'),
  ('ride_zemidjan_per_km_fcfa', 150,
   'Zémidjan : prix par km au-delà du 1er, FCFA. Valeur provisoire.'),
  ('ride_tricycle_base_fcfa',  1500,
   'Tricycle Fret : prix de départ (couvre le 1er km), FCFA. Valeur provisoire.'),
  ('ride_tricycle_per_km_fcfa', 400,
   'Tricycle Fret : prix par km au-delà du 1er, FCFA. Valeur provisoire.')
on conflict (key) do nothing;

commit;