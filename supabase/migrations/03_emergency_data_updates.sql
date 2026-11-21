-- =============================================================================
-- MONTOTEM : Script 03 - Données d'urgence par pays
-- Fichier  : 03_emergency_data_updates.sql
-- =============================================================================

begin;

-- 1. Création sécurisée de la table si elle n'existe pas encore
create table if not exists public.emergency_numbers (
  country_code text primary key check (length(country_code) = 2),
  country_name text not null,
  police       text not null,
  fire         text not null,
  ambulance    text not null,
  general      text,
  confidence   text not null default 'a_confirmer' check (confidence in ('officiel', 'recoupe', 'a_confirmer')),
  source       text,
  verified_at  date,
  updated_at   timestamptz not null default now()
);

-- 2. Insertion/Mise à jour pour le Togo (TG)
insert into public.emergency_numbers (
  country_code, country_name, police, fire, ambulance, general, confidence, source, verified_at
)
values (
  'TG', 'Togo', '117', '118', '8200', '112', 'officiel', 'Source officielle à citer', current_date
)
on conflict (country_code) do update
set confidence = excluded.confidence,
    source = excluded.source,
    verified_at = excluded.verified_at,
    updated_at = now();

commit;

-- Vérification
select * from public.emergency_numbers where country_code = 'TG';