-- ============================================================================
-- MonTotem — SOS PANNE : Script 04/10
-- Extension (additive) du profil prestataire pour le SOS :
--   vehicle_categories / habilitations / sos_services / tarifs garantis,
--   table provider_skill_codes (compétences validées par un admin),
--   pièces / stock dans provider_catalog_items existant.
--
-- Exécution : après les scripts 01-03. Non destructif, idempotent.
-- Prérequis : 01-03, tables public.profiles, public.providers (script 013),
--             public.wallets (script 015), public.provider_catalog_items (08/014).
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Colonnes SOS sur providers (additif — les colonnes existantes ne sont
--    jamais modifiées ; si elles existent déjà, rien ne se passe)
-- ---------------------------------------------------------------------------
alter table providers
  add column if not exists vehicle_categories text[] not null default '{}';
alter table providers
  add column if not exists habilitations     text[] not null default '{}';
alter table providers
  add column if not exists sos_services      text[] not null default '{}';
alter table providers
  add column if not exists tarif_km_fcfa     int not null default 100
    check (tarif_km_fcfa between 0 and 5000);
alter table providers
  add column if not exists frais_deplacement_min_fcfa int not null default 1000
    check (frais_deplacement_min_fcfa between 0 and 100000);
alter table providers
  add column if not exists rayon_max_km      int not null default 15
    check (rayon_max_km between 1 and 50);

create index if not exists providers_vehicle_categories_gin
  on providers using gin (vehicle_categories);

-- ---------------------------------------------------------------------------
-- 2. Compétences SOS validées par prestataire (required_skill_code vérifié)
-- ---------------------------------------------------------------------------
create table if not exists provider_skill_codes (
  provider_id uuid        not null references providers (id)          on delete cascade,
  skill_code  text        not null references sos_competences (code)  on delete cascade,
  valide      boolean     not null default false,
  created_at  timestamptz not null default now(),
  primary key (provider_id, skill_code)
);

create index if not exists provider_skill_codes_skill_idx
  on provider_skill_codes (skill_code) where valide;

-- ---------------------------------------------------------------------------
-- 3. Pièces / consommables et stock dans le catalogue existant
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.provider_catalog_items') is not null then
    execute 'alter table provider_catalog_items
               add column if not exists piece_code text';
    execute 'alter table provider_catalog_items
               add column if not exists piece_libelle text';
    execute 'alter table provider_catalog_items
               add column if not exists stock int not null default 0';
    execute 'create index if not exists provider_catalog_items_piece_idx
               on provider_catalog_items (piece_code)
               where piece_code is not null';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Si provider_kind est un type enum (pas une contrainte check), ajoute
--    sans risque le tricycle passager.
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_type t where t.typname = 'provider_kind') then
    begin
      execute 'alter type provider_kind add value if not exists ''tricycle_pax''';
    exception when others then
      null;
    end;
  end if;
end $$;

commit;