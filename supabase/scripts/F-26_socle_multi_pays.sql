-- ============================================================================
-- MonTotem — F-26 : SOCLE MULTI-PAYS (prêt pour l'Afrique de l'Ouest et au-delà)
-- ============================================================================
-- Principe : UNE SEULE base, mais chaque entité porte son pays et sa devise,
-- et chaque règle locale vit dans une table de configuration — jamais dans
-- du code en dur.
--
--  1. pays_config : devise, langue, format téléphonique, opérateurs Mobile
--     Money, commissions et moyens de paiement PAR PAYS (le Bénin actif,
--     les autres préparés mais désactivés tant qu'ils ne sont pas lancés).
--
--  2. zone_code + currency_code sur providers, missions, rides et wallets :
--     renseignés automatiquement à la création via le pays du profil
--     (déclencheurs — aucune régression des RPC F-19/F-20).
--
--  3. supervision_capacite() : le RPC admin qui lit les métriques de
--     croissance (lignes, tailles) pour décider QUAND monter le compute —
--     selon les métriques réelles, jamais à l'avance.
--
-- Déjà en place (audit F-26) : profiles.country_code, tables devises/zones,
-- devise_du_prestataire(), arrondir_devise(), compression d'images
-- (imageQuality 80-90 / maxWidth 1600-2000), cache local des tarifs
-- (LocalCache), file d'attente hors ligne (OutboxService).
--
-- Prérequis : finance/11 (devises ; zones BJ/NG/KE), 010 (profiles), 015/017 (wallets,
-- rides). Idempotent.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0. Zones des futurs pays (prérequis des clés étrangères de pays_config).
--    BJ, NG et KE existent déjà (migration finance/11). actif = false :
--    chaque pays sera activé le jour de son lancement (zones + pays_config).
-- ---------------------------------------------------------------------------
insert into public.zones (code, pays, devise_code, villes, actif) values
  ('TG', 'Togo',         'XOF',
   array['Lomé','Kara','Sokodé','Atakpamé','Aného'], false),
  ('BF', 'Burkina Faso', 'XOF',
   array['Ouagadougou','Bobo-Dioulasso','Koudougou'], false),
  ('CI', 'Côte d''Ivoire', 'XOF',
   array['Abidjan','Bouaké','Yamoussoukro','San-Pédro'], false),
  ('SN', 'Sénégal',      'XOF',
   array['Dakar','Thiès','Saint-Louis','Ziguinchor'], false),
  ('CM', 'Cameroun',     'XAF',
   array['Douala','Yaoundé','Bafoussam','Garoua'], false),
  ('GH', 'Ghana',        'GHS',
   array['Accra','Kumasi','Takoradi','Tamale'], false)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 1. Configuration par pays (règles locales externalisées)
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

-- Le Bénin est le SEUL pays actif au lancement ; les autres sont préparés.
insert into public.pays_config (country_code, nom_pays, devise_code, zone_code,
    langue_defaut, prefixe_tel, tel_chiffres, momo_operateurs,
    paiement_cash, actif) values
  ('BJ', 'Bénin',       'XOF', 'BJ', 'fr', '+229', 8,
   array['mtn','moov','celtiis'], true,  true),
  ('TG', 'Togo',        'XOF', 'TG', 'fr', '+228', 8,
   array['mtn','moov'], true, false),
  ('BF', 'Burkina Faso','XOF', 'BF', 'fr', '+226', 8,
   array['orange','mtn','moov'], true, false),
  ('CI', 'Côte d''Ivoire','XOF','CI', 'fr', '+225', 10,
   array['orange','mtn','moov','wave'], true, false),
  ('SN', 'Sénégal',     'XOF', 'SN', 'fr', '+221', 9,
   array['orange','freemoney','wave','emoney'], true, false),
  ('CM', 'Cameroun',    'XAF', 'CM', 'fr', '+237', 9,
   array['mtn','orange'], true, false),
  ('NG', 'Nigéria',     'NGN', 'NG', 'en', '+234', 10,
   array['mtn','airtel','glo','9mobile'], true, false),
  ('GH', 'Ghana',       'GHS', 'GH', 'en', '+233', 9,
   array['mtn','telecel','at'], true, false),
  ('KE', 'Kenya',       'KES', 'KE', 'en', '+254', 10,
   array['mpesa','airtel-money'], true, false)
on conflict (country_code) do nothing;

alter table public.pays_config enable row level security;

drop policy if exists pays_config_select on public.pays_config;
create policy pays_config_select on public.pays_config
  for select to anon, authenticated
  using (actif or public.is_admin());

revoke insert, update, delete on public.pays_config from authenticated, anon;

-- ---------------------------------------------------------------------------
-- 2. zone_code + currency_code sur les entités métier
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

-- Rattrapage : les entités existantes sont rattachées à la zone du profil.
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
-- 3. Déclencheurs : zone/devise remplie automatiquement à la création
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
  -- to_jsonb(new) : les 4 tables n'ont pas les mêmes colonnes (providers
  -- n'a pas client_id, wallets n'a pas client_id). On lit génériquement.
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
-- 4. Supervision capacité (décider de monter le compute sur des MÉTRIQUES)
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

commit;

-- ── Contrôles (à exécuter après le script) ──
-- SELECT country_code, devise_code, prefixe_tel, actif FROM public.pays_config ORDER BY country_code;
--   attendu : BJ actif = true ; les 8 autres actif = false.
-- SELECT zone_code, currency_code FROM public.missions WHERE zone_code IS NULL;
--   attendu : 0 ligne.
-- SELECT * FROM public.supervision_capacite();   -- en tant qu'admin
