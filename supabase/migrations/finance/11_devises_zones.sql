-- ============================================================================
-- MonTotem — FINANCE : Script 11/13
-- Modélisation multi-devise : stockage en unités mineures entières (bigint),
-- devise dictée par la zone/pays du service (jamais par un taux côté client).
--
--   - XOF / XAF : 0 décimale (unité entière) ;
--   - NGN / KES / GHS : 2 décimales (kobo, cents, pesewas) ;
--   - rounding_mode : ROUND | FLOOR | CEIL — arrondi explicite par devise,
--     appliqué UNIQUEMENT côté serveur.
--
-- Exécution : Supabase SQL Editor. Non destructif, idempotent.
-- Prérequis : aucun.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Référentiel des devises
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
-- 2. Zones de service : ville(s) → devise. Une course/prestation est facturée
--    dans la devise de la zone où elle se produit, jamais selon le client.
-- ---------------------------------------------------------------------------
create table if not exists public.zones (
  code        text primary key check (code ~ '^[A-Z]{2,3}$'),
  pays        text not null,
  devise_code text not null references public.devises (code),
  villes      text[] not null default '{}',
  actif       boolean not null default true
);

insert into public.zones (code, pays, devise_code, villes) values
  ('BJ', 'Bénin',   'XOF',
   array['Cotonou','Abomey-Calavi','Porto-Novo','Ouidah','Sèmè-Kpodji','Abomey','Bohicon','Parakou','Djougou','Natitingou']),
  ('NG', 'Nigéria', 'NGN', array['Lagos','Badagry','Ilorin']),
  ('KE', 'Kénya',   'KES', array['Nairobi','Mombasa']),
  ('GH', 'Ghana',   'GHS', array['Accra','Kumasi','Ho'])
on conflict (code) do update
  set devise_code = excluded.devise_code,
      villes      = excluded.villes;

-- ---------------------------------------------------------------------------
-- 3. Devise d'un prestataire : la ville de son profil détermine sa zone.
--    Ville inconnue ⇒ devise par défaut du projet (XOF).
-- ---------------------------------------------------------------------------
create or replace function public.devise_du_prestataire(p_provider uuid)
returns text
language sql
stable
security definer
set search_path = public, extensions
as $$
  select coalesce(
    (select z.devise_code
       from public.providers pv
       join public.zones z
         on z.villes @> array[lower(btrim(pv.ville))]
      where pv.id = p_provider
      limit 1),
    (select z.devise_code
       from public.zones z
       where z.code = 'BJ'))
$$;

revoke all on function public.devise_du_prestataire(uuid) from public;
grant execute on function public.devise_du_prestataire(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Arrondi explicite par devise (unités mineures entières uniquement)
-- ---------------------------------------------------------------------------
create or replace function public.arrondir_devise(
  p_montant numeric,
  p_devise  text
) returns bigint
language plpgsql
immutable
security definer
set search_path = public, extensions
as $$
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
$$;

revoke all on function public.arrondir_devise(numeric, text) from public;
grant execute on function public.arrondir_devise(numeric, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Accès : lecture publique des référentiels
-- ---------------------------------------------------------------------------
alter table public.devises enable row level security;
alter table public.zones   enable row level security;

drop policy if exists devises_lecture on public.devises;
create policy devises_lecture
  on public.devises for select using (true);

drop policy if exists zones_lecture on public.zones;
create policy zones_lecture
  on public.zones for select using (true);

grant select on public.devises to anon, authenticated;
grant select on public.zones   to anon, authenticated;

commit;