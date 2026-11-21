-- =============================================================================
-- 014 — Catalogue : prix fixés par le prestataire (prestation × véhicule)
-- Dart : provider_catalog_service.dart, provider_catalog_model.dart,
--        provider_skills_service.dart
-- Dépend de : 013
-- =============================================================================
begin;

set local search_path to public, extensions;

-- Dart : ProviderSkill (id, label)
create table if not exists public.provider_skills (
  id          uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.providers(id) on delete cascade,
  label       text not null check (char_length(label) between 2 and 60),
  created_at  timestamptz not null default now()
);
create unique index if not exists uq_provider_skills_label
  on public.provider_skills (provider_id, lower(label));

-- Dart : ServiceTarif (id, nom, categorie_vehicule, prix_fcfa)
-- Une ligne = (prestation × 1 véhicule × prix). Ex :
--   "Changement batterie" · moto    · 5000
--   "Changement batterie" · voiture · 8000
--   "Changement batterie" · camion  · 25000
create table if not exists public.provider_catalog_items (
  id                 uuid primary key default gen_random_uuid(),
  provider_id        uuid not null references public.providers(id) on delete cascade,
  nom                text not null check (char_length(btrim(nom)) between 2 and 80),
  categorie_vehicule text not null check (categorie_vehicule in
                       ('moto','tricycle','voiture','bus','camion')),
  prix_fcfa          integer not null check (prix_fcfa > 0 and prix_fcfa <= 10000000),
  created_at         timestamptz not null default now()
);

create index if not exists idx_catalog_items_provider
  on public.provider_catalog_items (provider_id, categorie_vehicule, created_at);
create unique index if not exists uq_catalog_items_nom_vehicule
  on public.provider_catalog_items (provider_id, lower(nom), categorie_vehicule);

-- Seul un garage peut publier une prestation de remorquage
create or replace function public.catalog_check_remorquage()
returns trigger language plpgsql set search_path = public
as $$
declare v_kind text;
begin
  if lower(new.nom) like '%remorqu%' then
    select provider_kind into v_kind
      from public.providers where id = new.provider_id;
    if v_kind <> 'garage' then
      raise exception 'REMORQUAGE_RESERVE_GARAGE' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_catalog_check_remorquage on public.provider_catalog_items;
create trigger trg_catalog_check_remorquage
  before insert or update on public.provider_catalog_items
  for each row execute function public.catalog_check_remorquage();

commit;