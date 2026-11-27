-- ============================================================================
-- MonTotem — F-27 : SCHÉMA MULTI-PAYS + POSTGIS COMPLET
-- ============================================================================
-- Script AUTONOME : il contient TOUT le socle multi-pays de MonTotem.
-- Il remplace F-26 (idempotent, peut tourner plusieurs fois sans erreur).
--
-- Contenu :
--   0. Extension PostGIS (géolocalisation native PostgreSQL).
--   1. devises    : XOF, XAF, NGN, KES, GHS (unités mineures entières).
--   2. zones      : BJ, TG, BF, CI, SN, CM, NG, GH, KE — les zones manquantes
--                   sont créées AVANT pays_config (jamais d'erreur FK).
--   3. pays_config: règles locales par pays (devise, langue, téléphone,
--                   Mobile Money, commissions, cash). Seul le Bénin est actif.
--   4. villes     : NOUVEAU — chaque ville avec un point geography(Point,4326),
--                   index GIST, recherche du plus proche (KNN PostGIS) et des
--                   villes dans un rayon donné.
--   5. zone_code + currency_code sur providers, missions, rides, wallets
--                   (rattrapage des lignes existantes inclus).
--   6. Déclencheurs : zone/devise remplis automatiquement à la création.
--   7. supervision_capacite() : RPC admin — métriques réelles de croissance.
--
-- Prérequis : migrations de base déjà appliquées (010 profiles, 013 providers,
-- 015 wallets, 016 missions, 017 rides) — c'est le cas de votre base.
-- Exécution : Supabase SQL Editor, script entier d'un coup.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0. Extension PostGIS (schéma extensions, déjà prévu par 001)
-- ---------------------------------------------------------------------------
create extension if not exists postgis with schema extensions;

-- ---------------------------------------------------------------------------
-- 1. Référentiel des devises
--    Montants stockés en unités mineures entières (bigint) : jamais de float.
--    XOF / XAF : 0 décimale. NGN / KES / GHS : 2 décimales.
-- ---------------------------------------------------------------------------
create table if not exists public.devises (
  code          text primary key check (code ~ '^[A-Z]{3}$'),
  libelle       text not null,
  minor_units   int not null default 0 check (minor_units in (0, 2)),
  rounding_mode text not null default 'ROUND'
                check (rounding_mode in ('ROUND', 'FLOOR', 'CEIL')),
  symbole       text not null default '',
  actif         boolean not null default true,
  position      int not null default 0
);

insert into public.devises (code, libelle, minor_units, rounding_mode, symbole, position) values
  ('XOF', 'Franc CFA (UEMOA)',  0, 'ROUND', 'FCFA', 10),
  ('XAF', 'Franc CFA (CEMAC)',  0, 'ROUND', 'FCFA', 20),
  ('NGN', 'Naira nigérian',     2, 'FLOOR', '₦',    30),
  ('KES', 'Shilling kényan',    2, 'ROUND', 'KSh',  40),
  ('GHS', 'Cedi ghanéen',       2, 'ROUND', 'GH₵',  50)
on conflict (code) do update
  set libelle       = excluded.libelle,
      minor_units   = excluded.minor_units,
      rounding_mode = excluded.rounding_mode,
      symbole       = excluded.symbole,
      position      = excluded.position;

-- ---------------------------------------------------------------------------
-- 2. Zones de service : une prestation est facturée dans la devise de la zone
--    où elle se produit, jamais selon le client. Les zones des futurs pays
--    sont créées ICI, avant pays_config (leçon F-26 : jamais de FK cassée).
--    actif = false : chaque pays sera activé le jour de son lancement.
-- ---------------------------------------------------------------------------
create table if not exists public.zones (
  code        text primary key check (code ~ '^[A-Z]{2,3}$'),
  pays        text not null,
  devise_code text not null references public.devises (code),
  villes      text[] not null default '{}',
  actif       boolean not null default true
);

insert into public.zones (code, pays, devise_code, villes, actif) values
  ('BJ', 'Bénin',         'XOF',
   array['Cotonou','Abomey-Calavi','Porto-Novo','Ouidah','Sèmè-Kpodji','Abomey','Bohicon','Parakou','Djougou','Natitingou'], true),
  ('TG', 'Togo',          'XOF',
   array['Lomé','Kara','Sokodé','Atakpamé','Aného'], false),
  ('BF', 'Burkina Faso',  'XOF',
   array['Ouagadougou','Bobo-Dioulasso','Koudougou'], false),
  ('CI', 'Côte d''Ivoire','XOF',
   array['Abidjan','Bouaké','Yamoussoukro','San-Pédro'], false),
  ('SN', 'Sénégal',       'XOF',
   array['Dakar','Thiès','Saint-Louis','Ziguinchor'], false),
  ('CM', 'Cameroun',      'XAF',
   array['Douala','Yaoundé','Bafoussam','Garoua'], false),
  ('NG', 'Nigéria',       'NGN',
   array['Lagos','Badagry','Ilorin'], false),
  ('GH', 'Ghana',         'GHS',
   array['Accra','Kumasi','Takoradi','Tamale','Ho'], false),
  ('KE', 'Kenya',         'KES',
   array['Nairobi','Mombasa'], false)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Configuration par pays : TOUTE règle locale vit ici, jamais en dur.
-- ---------------------------------------------------------------------------
create table if not exists public.pays_config (
  country_code                text primary key check (length(country_code) = 2),
  nom_pays                    text not null,
  devise_code                 text not null references public.devises (code),
  zone_code                   text references public.zones (code),
  langue_defaut               text not null default 'fr'
                              check (langue_defaut in ('fr','en','yo','fon')),
  prefixe_tel                 text not null default '+229',
  tel_chiffres                int not null default 8
                              check (tel_chiffres between 7 and 10),
  momo_operateurs             text[] not null default '{}',
  commission_ride_pourcent    numeric(4,2) not null default 10
                              check (commission_ride_pourcent between 0 and 30),
  commission_mission_pourcent numeric(4,2) not null default 10
                              check (commission_mission_pourcent between 0 and 30),
  paiement_cash               boolean not null default true,
  actif                       boolean not null default false,
  created_at                  timestamptz not null default now()
);

insert into public.pays_config (country_code, nom_pays, devise_code, zone_code,
    langue_defaut, prefixe_tel, tel_chiffres, momo_operateurs,
    paiement_cash, actif) values
  ('BJ', 'Bénin',        'XOF', 'BJ', 'fr', '+229', 8,
   array['mtn','moov','celtiis'], true,  true),
  ('TG', 'Togo',         'XOF', 'TG', 'fr', '+228', 8,
   array['mtn','moov'], true, false),
  ('BF', 'Burkina Faso', 'XOF', 'BF', 'fr', '+226', 8,
   array['orange','mtn','moov'], true, false),
  ('CI', 'Côte d''Ivoire','XOF','CI', 'fr', '+225', 10,
   array['orange','mtn','moov','wave'], true, false),
  ('SN', 'Sénégal',      'XOF', 'SN', 'fr', '+221', 9,
   array['orange','freemoney','wave','emoney'], true, false),
  ('CM', 'Cameroun',     'XAF', 'CM', 'fr', '+237', 9,
   array['mtn','orange'], true, false),
  ('NG', 'Nigéria',      'NGN', 'NG', 'en', '+234', 10,
   array['mtn','airtel','glo','9mobile'], true, false),
  ('GH', 'Ghana',        'GHS', 'GH', 'en', '+233', 9,
   array['mtn','telecel','at'], true, false),
  ('KE', 'Kenya',        'KES', 'KE', 'en', '+254', 10,
   array['mpesa','airtel-money'], true, false)
on conflict (country_code) do nothing;

alter table public.pays_config enable row level security;

drop policy if exists pays_config_select on public.pays_config;
create policy pays_config_select on public.pays_config
  for select to anon, authenticated
  using (actif or public.is_admin());

revoke insert, update, delete on public.pays_config from authenticated, anon;

-- ---------------------------------------------------------------------------
-- 4. VILLES + GÉOLOCALISATION (PostGIS)
--    Une ville = un point geography(Point,4326). Index GIST pour la recherche
--    du plus proche. nom_min (minuscules, sans espaces parasites) permet de
--    retrouver la ville depuis le champ libre du profil prestataire.
-- ---------------------------------------------------------------------------
create table if not exists public.villes (
  id         bigint generated always as identity primary key,
  pays_code  text not null references public.pays_config (country_code)
             on delete cascade,
  nom        text not null,
  nom_min    text generated always as (lower(btrim(nom))) stored,
  location   geography(Point, 4326) not null,
  population int,
  actif      boolean not null default true,
  created_at timestamptz not null default now(),
  unique (pays_code, nom_min)
);

create index if not exists idx_villes_location on public.villes using gist (location);
create index if not exists idx_villes_pays     on public.villes (pays_code);

-- Coordonnées officielles (latitude, longitude) des villes desservies.
-- BJ actif au lancement ; les autres pays seront activés avec leurs villes.
insert into public.villes (pays_code, nom, location, population, actif) values
  -- Bénin (actif)
  ('BJ', 'Cotonou',        st_setsrid(st_makepoint(  2.4183,  6.3654), 4326)::geography,  680000, true),
  ('BJ', 'Abomey-Calavi',  st_setsrid(st_makepoint(  2.3556,  6.4489), 4326)::geography,  660000, true),
  ('BJ', 'Porto-Novo',     st_setsrid(st_makepoint(  2.6289,  6.4969), 4326)::geography,  300000, true),
  ('BJ', 'Ouidah',         st_setsrid(st_makepoint(  2.0852,  6.3631), 4326)::geography,   47000, true),
  ('BJ', 'Sèmè-Kpodji',    st_setsrid(st_makepoint(  2.6042,  6.5225), 4326)::geography,   60000, true),
  ('BJ', 'Abomey',         st_setsrid(st_makepoint(  1.9912,  7.1862), 4326)::geography,   66000, true),
  ('BJ', 'Bohicon',        st_setsrid(st_makepoint(  2.0833,  7.1833), 4326)::geography,   70000, true),
  ('BJ', 'Parakou',        st_setsrid(st_makepoint(  2.6106,  9.3372), 4326)::geography,  260000, true),
  ('BJ', 'Djougou',        st_setsrid(st_makepoint(  1.6667,  9.7086), 4326)::geography,   95000, true),
  ('BJ', 'Natitingou',     st_setsrid(st_makepoint(  1.3806, 10.3053), 4326)::geography,   60000, true),
  -- Togo
  ('TG', 'Lomé',           st_setsrid(st_makepoint(  1.2228,  6.1319), 4326)::geography, 1800000, false),
  ('TG', 'Kara',           st_setsrid(st_makepoint(  1.1861,  9.5511), 4326)::geography,  100000, false),
  ('TG', 'Sokodé',         st_setsrid(st_makepoint(  1.1333,  8.9833), 4326)::geography,  120000, false),
  ('TG', 'Atakpamé',       st_setsrid(st_makepoint(  1.1333,  7.5333), 4326)::geography,   85000, false),
  ('TG', 'Aného',          st_setsrid(st_makepoint(  1.6000,  6.2333), 4326)::geography,   30000, false),
  -- Burkina Faso
  ('BF', 'Ouagadougou',    st_setsrid(st_makepoint( -1.5197, 12.3714), 4326)::geography, 2400000, false),
  ('BF', 'Bobo-Dioulasso', st_setsrid(st_makepoint( -4.2979, 11.1771), 4326)::geography,  900000, false),
  ('BF', 'Koudougou',      st_setsrid(st_makepoint( -2.3625, 12.2526), 4326)::geography,  160000, false),
  -- Côte d'Ivoire
  ('CI', 'Abidjan',        st_setsrid(st_makepoint( -4.0083,  5.3599), 4326)::geography, 5200000, false),
  ('CI', 'Bouaké',         st_setsrid(st_makepoint( -5.0300,  7.6906), 4326)::geography,  650000, false),
  ('CI', 'Yamoussoukro',   st_setsrid(st_makepoint( -5.2893,  6.8276), 4326)::geography,  355000, false),
  ('CI', 'San-Pédro',      st_setsrid(st_makepoint( -6.6363,  4.7485), 4326)::geography,  330000, false),
  -- Sénégal
  ('SN', 'Dakar',          st_setsrid(st_makepoint(-17.4677, 14.7167), 4326)::geography, 3000000, false),
  ('SN', 'Thiès',          st_setsrid(st_makepoint(-16.9333, 14.7833), 4326)::geography,  320000, false),
  ('SN', 'Saint-Louis',    st_setsrid(st_makepoint(-16.4818, 16.0326), 4326)::geography,  260000, false),
  ('SN', 'Ziguinchor',     st_setsrid(st_makepoint(-16.2719, 12.5833), 4326)::geography,  215000, false),
  -- Cameroun
  ('CM', 'Douala',         st_setsrid(st_makepoint(  9.7679,  4.0511), 4326)::geography, 3700000, false),
  ('CM', 'Yaoundé',        st_setsrid(st_makepoint( 11.5021,  3.8480), 4326)::geography, 4100000, false),
  ('CM', 'Bafoussam',      st_setsrid(st_makepoint( 10.4176,  5.4781), 4326)::geography,  350000, false),
  ('CM', 'Garoua',         st_setsrid(st_makepoint( 13.4000,  9.3000), 4326)::geography,  600000, false),
  -- Nigéria
  ('NG', 'Lagos',          st_setsrid(st_makepoint(  3.3792,  6.5244), 4326)::geography,15000000, false),
  ('NG', 'Badagry',        st_setsrid(st_makepoint(  2.8833,  6.4167), 4326)::geography,  240000, false),
  ('NG', 'Ilorin',         st_setsrid(st_makepoint(  4.5421,  8.4966), 4326)::geography,  950000, false),
  -- Ghana
  ('GH', 'Accra',          st_setsrid(st_makepoint( -0.1870,  5.6037), 4326)::geography, 2500000, false),
  ('GH', 'Kumasi',         st_setsrid(st_makepoint( -1.6244,  6.6885), 4326)::geography, 2200000, false),
  ('GH', 'Takoradi',       st_setsrid(st_makepoint( -1.7554,  4.8956), 4326)::geography,  240000, false),
  ('GH', 'Tamale',         st_setsrid(st_makepoint( -0.8393,  9.4008), 4326)::geography,  370000, false),
  ('GH', 'Ho',             st_setsrid(st_makepoint(  0.4714,  6.6111), 4326)::geography,  180000, false),
  -- Kenya
  ('KE', 'Nairobi',        st_setsrid(st_makepoint( 36.8172, -1.2864), 4326)::geography, 4700000, false),
  ('KE', 'Mombasa',        st_setsrid(st_makepoint( 39.6682, -4.0435), 4326)::geography, 1200000, false)
on conflict (pays_code, nom_min) do nothing;

alter table public.villes enable row level security;

drop policy if exists villes_lecture on public.villes;
create policy villes_lecture on public.villes
  for select to anon, authenticated
  using (true);

revoke insert, update, delete on public.villes from authenticated, anon;

-- 4a. Ville la plus proche d'une position GPS (KNN PostGIS, index GIST).
--     Ligne fantôme : renvoie TOUJOURS exactement 1 résultat (repli Cotonou).
create or replace function public.ville_la_plus_proche(
  p_lat double precision,
  p_lng double precision
)
returns record
language sql
stable
set search_path = public, extensions
as $func$
  select coalesce(v.nom, 'Cotonou') as nom,
         coalesce(v.pays_code, 'BJ') as pays
  from (select 1) as d
  left join lateral (
    select nom, pays_code
      from public.villes
     where actif
     order by location <-> st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography
     limit 1
  ) v on true;
$func$;

revoke all on function public.ville_la_plus_proche(double precision, double precision) from public;
grant execute on function public.ville_la_plus_proche(double precision, double precision)
  to anon, authenticated;

-- 4b. Villes actives dans un rayon donné (par défaut 50 km), les plus proches
--     d'abord — pour afficher les zones couvertes autour de l'utilisateur.
create or replace function public.villes_proches(
  p_lat double precision,
  p_lng double precision,
  p_km  double precision default 50
)
returns table (nom text, pays text, distance_km double precision)
language sql
stable
set search_path = public, extensions
as $func$
  select v.nom,
         v.pays_code,
         (st_distance(v.location,
                      st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography)
          / 1000.0)::double precision as distance_km
    from public.villes v
   where v.actif
     and st_dwithin(v.location,
                    st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
                    p_km * 1000.0)
   order by v.location <-> st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography
   limit 12;
$func$;

revoke all on function public.villes_proches(double precision, double precision, double precision) from public;
grant execute on function public.villes_proches(double precision, double precision, double precision)
  to anon, authenticated;

-- 4c. Zone + devise d'une ville (remplace la recherche par tableau zones.villes).
--     Ligne fantôme : repli Bénin/XOF si la ville est inconnue.
create or replace function public.zone_de_ville(p_ville text)
returns record
language sql
stable
as $func$
  select coalesce(pc.zone_code, 'BJ') as zone,
         coalesce(pc.devise_code, 'XOF') as devise
  from (select 1) as d
  left join lateral (
    select v.pays_code
      from public.villes v
     where v.nom_min = lower(btrim(coalesce(p_ville, '')))
       and v.actif
     order by v.population desc nulls last
     limit 1
  ) v on true
  left join public.pays_config pc on pc.country_code = v.pays_code;
$func$;

revoke all on function public.zone_de_ville(text) from public;
grant execute on function public.zone_de_ville(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. zone_code + currency_code sur les entités métier
-- ---------------------------------------------------------------------------
alter table public.providers add column if not exists zone_code     text;
alter table public.providers add column if not exists currency_code text;
alter table public.missions  add column if not exists zone_code     text;
alter table public.missions  add column if not exists currency_code text;
alter table public.rides     add column if not exists zone_code     text;
alter table public.rides     add column if not exists currency_code text;
alter table public.wallets   add column if not exists zone_code     text;
alter table public.wallets   add column if not exists currency_code text;

create index if not exists idx_providers_zone on public.providers (zone_code)
  where statut_validation = 'approved';
create index if not exists idx_missions_zone  on public.missions (zone_code, created_at desc);
create index if not exists idx_rides_zone     on public.rides (zone_code, created_at desc);

-- Rattrapage : les lignes existantes sont rattachées au pays du profil.
update public.providers p
   set zone_code     = c.country_code,
       currency_code = coalesce(c.devise_code, 'XOF')
  from public.profiles c
 where c.id = p.id and p.zone_code is null;

update public.missions m
   set zone_code     = c.country_code,
       currency_code = coalesce(c.devise_code, 'XOF')
  from public.profiles c
 where c.id = m.client_id and m.zone_code is null;

update public.rides r
   set zone_code     = c.country_code,
       currency_code = coalesce(c.devise_code, 'XOF')
  from public.profiles c
 where c.id = r.client_id and r.zone_code is null;

update public.wallets w
   set zone_code     = c.country_code,
       currency_code = coalesce(c.devise_code, 'XOF')
  from public.profiles c
 where c.id = w.provider_id and w.zone_code is null;

-- ---------------------------------------------------------------------------
-- 6. Déclencheurs : zone/devise remplis automatiquement à la création
-- ---------------------------------------------------------------------------
create or replace function public.devise_pays(p_pays text)
returns record
language sql
stable
as $func$
  -- La ligne fantôme garantit TOUJOURS exactement 1 résultat
  -- (repli Bénin/XOF si le pays n'a pas de zone active).
  select coalesce(z.code, 'BJ') as zone,
         coalesce(z.devise_code, 'XOF') as devise
  from (select 1) as d
  left join public.zones z
    on z.code = upper(btrim(coalesce(p_pays, ''))) and z.actif;
$func$;

create or replace function public.stamp_zone_devise()
returns trigger
language plpgsql
security definer
set search_path = public
as $func$
declare
  v_uid  uuid;
  v_pays text;
  r      record;
begin
  -- to_jsonb(new) : les 4 tables n'ont pas les mêmes colonnes (providers et
  -- wallets n'ont pas client_id). On lit le porteur du pays génériquement.
  v_uid := (coalesce(
    to_jsonb(new) ->> 'client_id',
    to_jsonb(new) ->> 'provider_id',
    to_jsonb(new) ->> 'id'))::uuid;
  if v_uid is null then v_uid := '00000000-0000-0000-0000-000000000000'; end if;
  v_pays := (select c.country_code from public.profiles c
              where c.id = v_uid);
  if v_pays is null then v_pays := 'BJ'; end if;
  select * into r from public.devise_pays(v_pays);
  new.zone_code     := coalesce(r.zone, 'BJ');
  new.currency_code := coalesce(r.devise, 'XOF');
  return new;
end;
$func$;

drop trigger if exists trg_missions_zone on public.missions;
create trigger trg_missions_zone
  before insert on public.missions
  for each row execute function public.stamp_zone_devise();

drop trigger if exists trg_rides_zone on public.rides;
create trigger trg_rides_zone
  before insert on public.rides
  for each row execute function public.stamp_zone_devise();

drop trigger if exists trg_providers_zone on public.providers;
create trigger trg_providers_zone
  before insert on public.providers
  for each row execute function public.stamp_zone_devise();

drop trigger if exists trg_wallets_zone on public.wallets;
create trigger trg_wallets_zone
  before insert on public.wallets
  for each row execute function public.stamp_zone_devise();

-- ---------------------------------------------------------------------------
-- 7. Supervision capacité : décider de monter le compute sur des MÉTRIQUES
--    (taille de base, lignes, connexions) — jamais à l'avance.
-- ---------------------------------------------------------------------------
create or replace function public.supervision_capacite()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $func$
begin
  if not public.is_admin() then
    raise exception 'RESERVE_ADMIN' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'base_octets', pg_database_size(current_database()),
    'tables', (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'table',   t.relname,
            'lignes',  t.n_live_tup,
            'octets',  pg_total_relation_size(t.relid)
          )
          order by pg_total_relation_size(t.relid) desc
        ),
        '[]'::jsonb
      )
      from pg_stat_user_tables t
    ),
    'connexions', (select count(*) from pg_stat_activity where datname = current_database()),
    'genere_le',  now()
  );
end;
$func$;
revoke all on function public.supervision_capacite() from public, anon;
grant execute on function public.supervision_capacite() to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Arrondi explicite par devise (rappel du socle finance, idempotent)
-- ---------------------------------------------------------------------------
create or replace function public.arrondir_devise(
  p_montant numeric,
  p_devise  text
) returns bigint
language plpgsql
immutable
security definer
set search_path = public, extensions
as $func$
declare
  v_mode text;
begin
  select rounding_mode into v_mode
    from public.devises where code = upper(btrim(p_devise)) and actif;
  v_mode := coalesce(v_mode, 'ROUND');
  case v_mode
    when 'FLOOR' then return floor(p_montant)::bigint;
    when 'CEIL'  then return ceil(p_montant)::bigint;
    else              return round(p_montant)::bigint;
  end case;
end;
$func$;

revoke all on function public.arrondir_devise(numeric, text) from public;
grant execute on function public.arrondir_devise(numeric, text) to anon, authenticated;

commit;

-- ── Contrôles (à exécuter après le script) ──────────────────────────────────
-- SELECT code, pays, devise_code, actif FROM public.zones ORDER BY code;
--   attendu : 9 zones (BJ TG BF CI SN CM NG GH KE).
-- SELECT country_code, devise_code, prefixe_tel, actif FROM public.pays_config ORDER BY country_code;
--   attendu : BJ actif = true ; les 8 autres actif = false.
-- SELECT pays_code, nom FROM public.villes ORDER BY pays_code, nom;
--   attendu : 41 villes.
-- SELECT * FROM public.ville_la_plus_proche(6.37, 2.42);
--   attendu : Cotonou, BJ.
-- SELECT * FROM public.villes_proches(6.37, 2.42, 60);
--   attendu : Cotonou, Abomey-Calavi, Porto-Novo, Ouidah...
-- SELECT zone, devise FROM public.zone_de_ville('Abomey-Calavi');
--   attendu : BJ, XOF.
-- SELECT zone_code, currency_code FROM public.missions WHERE zone_code IS NULL;
--   attendu : 0 ligne.
-- SELECT * FROM public.supervision_capacite();   -- en tant qu'admin
