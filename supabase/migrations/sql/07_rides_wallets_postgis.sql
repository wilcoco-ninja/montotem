-- =============================================================================
-- MONTOTEM : Script 07 - PostGIS, wallets, courses (rides), rôles admin, RLS
-- Fichier  : sql/07_rides_wallets_postgis.sql
-- Idempotent : peut être rejoué sans erreur.
-- =============================================================================

begin;

create extension if not exists postgis with schema extensions;

set local search_path to public, extensions;

-- -------------------------------------------------------------------------------
-- 1. Configuration plateforme (commission, seuil de blocage)
-- -----------------------------------------------------------------------------
create table if not exists public.app_config (
  key        text primary key,
  value_int  integer,
  note       text,
  updated_at timestamptz not null default now()
);

insert into public.app_config (key, value_int, note) values
  ('commission_cash_pct',          15,    'Commission (%) prélevée sur les courses payées en cash'),
  ('wallet_block_threshold_fcfa',  -2000, 'Le prestataire est bloqué si son solde passe sous ce seuil (FCFA)')
on conflict (key) do nothing;

-- -------------------------------------------------------------------------------
-- 2. Fonctions utilitaires
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- -------------------------------------------------------------------------------
-- 3. Profils : colonnes complémentaires
-- -----------------------------------------------------------------------------
alter table public.profiles
  add column if not exists country_code text not null default 'BJ',
  add column if not exists is_suspended boolean not null default false;

-- -------------------------------------------------------------------------------
-- 4. Rôles administrateur
-- -----------------------------------------------------------------------------
create table if not exists public.admin_roles (
  user_id    uuid primary key references public.profiles (id) on delete cascade,
  level      text not null default 'support'
             check (level in ('super_admin', 'finance', 'support', 'moderator')),
  granted_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
           select 1 from public.profiles p
            where p.id = auth.uid() and p.role = 'admin'
         )
      or exists (
           select 1 from public.admin_roles a
            where a.user_id = auth.uid()
         );
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public, extensions
as $$
  select exists (
    select 1 from public.admin_roles a
     where a.user_id = auth.uid() and a.level = 'super_admin'
  );
$$;

-- -------------------------------------------------------------------------------
-- 5. Prestataires : type de service + position géographique PostGIS
-- -----------------------------------------------------------------------------
alter table public.providers
  add column if not exists provider_kind text,
  add column if not exists location geography(Point, 4326);

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'providers_provider_kind_check'
  ) then
    alter table public.providers
      add constraint providers_provider_kind_check
      check (provider_kind is null or provider_kind in (
        'zemidjan', 'tricycle_fret', 'vulcanisateur', 'mecanicien',
        'electricien', 'station', 'garage'
      ));
  end if;
end $$;

create or replace function public.providers_sync_location()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  if new.latitude is not null and new.longitude is not null then
    new.location := st_setsrid(st_makepoint(new.longitude, new.latitude), 4326)::geography;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_providers_sync_location on public.providers;
create trigger trg_providers_sync_location
  before insert or update of latitude, longitude on public.providers
  for each row execute function public.providers_sync_location();

-- Rattrapage des prestataires existants.
update public.providers
   set location = st_setsrid(st_makepoint(longitude, latitude), 4326)::geography
 where location is null
   and latitude is not null and longitude is not null;

create index if not exists idx_providers_location on public.providers using gist (location);
create index if not exists idx_providers_kind     on public.providers (provider_kind);

-- -------------------------------------------------------------------------------
-- 6. Wallets prestataires + grand livre
-- -----------------------------------------------------------------------------
create table if not exists public.wallets (
  provider_id  uuid primary key references public.providers (id) on delete cascade,
  balance_fcfa integer not null default 0,
  blocked      boolean not null default false,
  blocked_at   timestamptz,
  block_reason text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table if not exists public.wallet_transactions (
  id            bigint generated always as identity primary key,
  provider_id   uuid not null references public.wallets (provider_id) on delete cascade,
  ride_id       uuid,
  kind          text not null
                check (kind in ('commission_cash', 'topup', 'adjustment', 'refund')),
  amount_fcfa   integer not null check (amount_fcfa <> 0),
  balance_after integer not null,
  reference     text,
  note          text,
  created_by    uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now()
);

create index if not exists idx_wallet_tx_provider on public.wallet_transactions (provider_id, created_at desc);
create unique index if not exists uq_wallet_tx_reference  on public.wallet_transactions (reference) where reference is not null;
create unique index if not exists uq_wallet_tx_ride_commission  on public.wallet_transactions (ride_id) where kind = 'commission_cash';

-- Création automatique du wallet à l'inscription d'un prestataire.
create or replace function public.providers_create_wallet()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  insert into public.wallets (provider_id) values (new.id) on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists trg_providers_create_wallet on public.providers;
create trigger trg_providers_create_wallet
  after insert on public.providers
  for each row execute function public.providers_create_wallet();

-- Rattrapage des prestataires existants.
insert into public.wallets (provider_id)
select id from public.providers
on conflict do nothing;

-- Blocage / déblocage automatique selon le solde.
create or replace function public.wallets_auto_block()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_threshold integer;
begin
  select value_int into v_threshold
    from public.app_config where key = 'wallet_block_threshold_fcfa';
  v_threshold := coalesce(v_threshold, -2000);
  new.updated_at := now();

  if new.balance_fcfa < v_threshold then
    if not new.blocked then
      new.blocked      := true;
      new.blocked_at   := now();
      new.block_reason := 'WALLET_SOUS_SEUIL';
    end if;
  elsif new.blocked and new.block_reason = 'WALLET_SOUS_SEUIL' then
    new.blocked      := false;
    new.blocked_at   := null;
    new.block_reason := null;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_wallets_auto_block on public.wallets;
create trigger trg_wallets_auto_block
  before insert or update of balance_fcfa on public.wallets
  for each row execute function public.wallets_auto_block();

-- Effets de bord : hors ligne + notification quand l'état de blocage change.
create or replace function public.wallets_after_block_change()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.blocked and not old.blocked then
    update public.providers set disponible = false where id = new.provider_id;
    begin
      perform public.notify_user(
        new.provider_id, 'wallet_blocked', 'Compte bloqué',
        'Votre solde est inférieur au seuil autorisé. Rechargez votre wallet pour reprendre les courses.',
        jsonb_build_object('balance_fcfa', new.balance_fcfa)
      );
    exception when others then
      null;
    end;
  elsif old.blocked and not new.blocked then
    begin
      perform public.notify_user(
        new.provider_id, 'wallet_unblocked', 'Compte débloqué',
        'Votre wallet est de nouveau à jour. Vous pouvez reprendre les courses.',
        jsonb_build_object('balance_fcfa', new.balance_fcfa)
      );
    exception when others then
      null;
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_wallets_after_block_change on public.wallets;
create trigger trg_wallets_after_block_change
  after update of blocked on public.wallets
  for each row execute function public.wallets_after_block_change();

-- -------------------------------------------------------------------------------
-- 7. Courses (Zémidjan, Tricycle Fret, ...)
-- -----------------------------------------------------------------------------
create table if not exists public.rides (
  id                 uuid primary key default gen_random_uuid(),
  client_id          uuid not null references public.profiles (id) on delete cascade,
  provider_id        uuid references public.providers (id) on delete set null,
  service_kind       text not null
                     check (service_kind in ('zemidjan', 'tricycle_fret')),
  status             text not null default 'requested'
                     check (status in ('requested', 'accepted', 'arrived', 'in_progress', 'completed', 'cancelled')),
  pickup             geography(Point, 4326) not null,
  dropoff            geography(Point, 4326) not null,
  pickup_address     text,
  dropoff_address    text,
  distance_m         integer not null default 0 check (distance_m >= 0),
  fare_fcfa          integer not null check (fare_fcfa between 100 and 500000),
  final_fare_fcfa    integer check (final_fare_fcfa is null or final_fare_fcfa between 100 and 500000),
  payment_method     text not null default 'cash'
                     check (payment_method in ('cash', 'mtn', 'moov', 'celtiis')),
  commission_fcfa    integer not null default 0 check (commission_fcfa >= 0),
  commission_applied boolean not null default false,
  cancel_reason      text,
  cancelled_by       uuid references public.profiles (id) on delete set null,
  accepted_at        timestamptz,
  arrived_at         timestamptz,
  started_at         timestamptz,
  completed_at       timestamptz,
  cancelled_at       timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint rides_provider_not_client check (provider_id is null or provider_id <> client_id)
);

create index if not exists idx_rides_client   on public.rides (client_id, created_at desc);
create index if not exists idx_rides_provider on public.rides (provider_id, created_at desc);
create index if not exists idx_rides_open     on public.rides (service_kind, created_at desc) where status = 'requested';
create index if not exists idx_rides_pickup   on public.rides using gist (pickup);

drop trigger if exists trg_rides_updated_at on public.rides;
create trigger trg_rides_updated_at
  before update on public.rides
  for each row execute function public.set_updated_at();

-- Commission cash : déduite du wallet à la clôture de la course.
create or replace function public.rides_apply_commission()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_pct  integer;
  v_base integer;
  v_comm integer;
  v_bal  integer;
begin
  new.completed_at    := coalesce(new.completed_at, now());
  new.final_fare_fcfa := coalesce(new.final_fare_fcfa, new.fare_fcfa);
  v_base := new.final_fare_fcfa;

  if new.payment_method <> 'cash'
     or new.commission_applied
     or new.provider_id is null then
    return new;
  end if;

  select value_int into v_pct
    from public.app_config where key = 'commission_cash_pct';
  v_pct  := coalesce(v_pct, 15);
  v_comm := round(v_base * v_pct / 100.0)::integer;

  if v_comm > 0 then
    insert into public.wallets (provider_id) values (new.provider_id)
      on conflict do nothing;

    update public.wallets
       set balance_fcfa = balance_fcfa - v_comm
     where provider_id = new.provider_id
    returning balance_fcfa into v_bal;

    insert into public.wallet_transactions
      (provider_id, ride_id, kind, amount_fcfa, balance_after, note)
    values
      (new.provider_id, new.id, 'commission_cash', -v_comm, v_bal,
       'Commission ' || v_pct || ' % sur course cash de ' || v_base || ' FCFA');
  end if;

  new.commission_fcfa    := v_comm;
  new.commission_applied := true;
  return new;
end;
$$;

drop trigger if exists trg_rides_apply_commission on public.rides;
create trigger trg_rides_apply_commission
  before update of status on public.rides
  for each row
  when (new.status = 'completed' and old.status is distinct from 'completed')
  execute function public.rides_apply_commission();

-- Garde : un prestataire bloqué ne peut pas accepter (rides).
create or replace function public.guard_blocked_provider()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if new.status = 'accepted' and old.status = 'requested' and new.provider_id is not null then
    if exists (
      select 1 from public.wallets w
       where w.provider_id = new.provider_id and w.blocked
    ) then
      raise exception 'WALLET_BLOQUE' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_rides_guard_blocked on public.rides;
create trigger trg_rides_guard_blocked
  before update of status on public.rides
  for each row execute function public.guard_blocked_provider();

-- Même garde sur les missions de dépannage existantes.
do $$
begin
  if to_regclass('public.missions') is not null then
    execute 'drop trigger if exists trg_missions_guard_blocked on public.missions';
    execute 'create trigger trg_missions_guard_blocked
               before update of status on public.missions
               for each row execute function public.guard_blocked_provider()';
  end if;
end $$;

-- -------------------------------------------------------------------------------
-- 8. RPC : courses
-- -----------------------------------------------------------------------------
create or replace function public.create_ride(
  p_service_kind    text,
  p_pickup_lat      double precision,
  p_pickup_lng      double precision,
  p_dropoff_lat     double precision,
  p_dropoff_lng     double precision,
  p_fare_fcfa       integer,
  p_payment_method  text default 'cash',
  p_pickup_address  text default null,
  p_dropoff_address text default null
) returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid    uuid := auth.uid();
  v_pickup geography;
  v_drop   geography;
  v_id     uuid;
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;

  if p_service_kind not in ('zemidjan', 'tricycle_fret') then
    raise exception 'SERVICE_INVALIDE' using errcode = '22023';
  end if;

  if p_payment_method not in ('cash', 'mtn', 'moov', 'celtiis') then
    raise exception 'PAIEMENT_INVALIDE' using errcode = '22023';
  end if;

  if p_fare_fcfa is null or p_fare_fcfa < 100 or p_fare_fcfa > 500000 then
    raise exception 'TARIF_INVALIDE' using errcode = '22023';
  end if;

  if p_pickup_lat not between -90 and 90 or p_dropoff_lat not between -90 and 90
     or p_pickup_lng not between -180 and 180 or p_dropoff_lng not between -180 and 180 then
    raise exception 'POSITION_INVALIDE' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.rides r
     where r.client_id = v_uid and r.status in ('requested', 'accepted', 'arrived', 'in_progress')
  ) then
    raise exception 'COURSE_EN_COURS' using errcode = 'P0001';
  end if;

  v_pickup := st_setsrid(st_makepoint(p_pickup_lng,  p_pickup_lat),  4326)::geography;
  v_drop   := st_setsrid(st_makepoint(p_dropoff_lng, p_dropoff_lat), 4326)::geography;

  insert into public.rides
    (client_id, service_kind, pickup, dropoff, pickup_address, dropoff_address,
     distance_m, fare_fcfa, payment_method)
  values
    (v_uid, p_service_kind, v_pickup, v_drop,
     left(nullif(btrim(p_pickup_address), ''), 300),
     left(nullif(btrim(p_dropoff_address), ''), 300),
     round(st_distance(v_pickup, v_drop))::integer, p_fare_fcfa, p_payment_method)
  returning id into v_id;

  return v_id;
end;
$$;

-- Actions : accept | arrived | start | complete | cancel
create or replace function public.ride_action(
  p_ride   uuid,
  p_action text,
  p_fare   integer default null,
  p_reason text default null
) returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_r   public.rides%rowtype;
  v_pv  public.providers%rowtype;
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;

  select * into v_r from public.rides where id = p_ride for update;
  if not found then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;

  if p_action = 'accept' then
    if v_r.status <> 'requested' or v_r.provider_id is not null then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;

    if v_r.client_id = v_uid then
      raise exception 'INTERDIT' using errcode = '42501';
    end if;

    select * into v_pv from public.providers pv
     where pv.id = v_uid
       and pv.statut_validation = 'approved'
       and pv.fin_abonnement > now();

    if not found then
      raise exception 'PRESTATAIRE_NON_ACTIF' using errcode = 'P0001';
    end if;

    if v_pv.provider_kind is distinct from v_r.service_kind then
      raise exception 'SERVICE_INCOMPATIBLE' using errcode = 'P0001';
    end if;

    update public.rides
       set provider_id = v_uid, status = 'accepted', accepted_at = now()
     where id = v_r.id;

    return 'accepted';

  elsif p_action in ('arrived', 'start', 'complete') then
    if v_r.provider_id is distinct from v_uid then
      raise exception 'INTERDIT' using errcode = '42501';
    end if;

    if p_action = 'arrived' then
      if v_r.status <> 'accepted' then
        raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
      end if;
      update public.rides set status = 'arrived', arrived_at = now() where id = v_r.id;
      return 'arrived';

    elsif p_action = 'start' then
      if v_r.status <> 'arrived' then
        raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
      end if;
      update public.rides set status = 'in_progress', started_at = now() where id = v_r.id;
      return 'in_progress';

    else
      if v_r.status <> 'in_progress' then
        raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
      end if;

      if p_fare is not null and (p_fare < 100 or p_fare > 500000) then
        raise exception 'TARIF_INVALIDE' using errcode = '22023';
      end if;

      update public.rides
         set status = 'completed',
             final_fare_fcfa = coalesce(p_fare, fare_fcfa)
       where id = v_r.id;

      return 'completed';
    end if;

  elsif p_action = 'cancel' then
    if v_uid not in (v_r.client_id, coalesce(v_r.provider_id, v_r.client_id)) then
      raise exception 'INTERDIT' using errcode = '42501';
    end if;

    if v_r.status in ('completed', 'cancelled', 'in_progress') then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;

    update public.rides
       set status = 'cancelled', cancelled_at = now(), cancelled_by = v_uid,
           cancel_reason = left(nullif(btrim(p_reason), ''), 300)
     where id = v_r.id;

    return 'cancelled';
  end if;

  raise exception 'ACTION_INVALIDE' using errcode = '22023';
end;
$$;

-- Courses ouvertes autour du prestataire connecté (vide si wallet bloqué).
create or replace function public.rides_nearby(
  p_lat       double precision,
  p_lng       double precision,
  p_radius_km numeric default 5
) returns table (
  id                   uuid,
  service_kind         text,
  pickup_address       text,
  dropoff_address      text,
  fare_fcfa            integer,
  payment_method       text,
  distance_to_pickup_m integer,
  trip_distance_m      integer,
  created_at           timestamptz
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_uid  uuid := auth.uid();
  v_kind text;
  v_here geography;
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;

  select pv.provider_kind into v_kind
    from public.providers pv
   where pv.id = v_uid
     and pv.statut_validation = 'approved'
     and pv.fin_abonnement > now();

  if v_kind is null then
    return;
  end if;

  if exists (select 1 from public.wallets w where w.provider_id = v_uid and w.blocked) then
    return;
  end if;

  v_here := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;

  return query
  select r.id,
         r.service_kind,
         r.pickup_address,
         r.dropoff_address,
         r.fare_fcfa,
         r.payment_method,
         round(st_distance(r.pickup, v_here))::integer,
         r.distance_m,
         r.created_at
    from public.rides r
   where r.status = 'requested'
     and r.provider_id is null
     and r.service_kind = v_kind
     and r.client_id <> v_uid
     and r.created_at > now() - interval '30 minutes'
     and st_dwithin(r.pickup, v_here, least(greatest(p_radius_km, 0.1), 50) * 1000)
   order by st_distance(r.pickup, v_here)
   limit 30;
end;
$$;

-- -------------------------------------------------------------------------------
-- 9. RPC admin : crédit / ajustement du wallet
-- -----------------------------------------------------------------------------
create or replace function public.admin_credit_wallet(
  p_provider  uuid,
  p_amount    integer,
  p_reference text default null,
  p_note      text default null
) returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_bal integer;
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;

  if p_amount is null or p_amount = 0 or abs(p_amount) > 10000000 then
    raise exception 'MONTANT_INVALIDE' using errcode = '22023';
  end if;

  if not exists (select 1 from public.providers where id = p_provider) then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;

  insert into public.wallets (provider_id) values (p_provider) on conflict do nothing;

  update public.wallets
     set balance_fcfa = balance_fcfa + p_amount
   where provider_id = p_provider
  returning balance_fcfa into v_bal;

  insert into public.wallet_transactions
    (provider_id, kind, amount_fcfa, balance_after, reference, note, created_by)
  values
    (p_provider,
     case when p_amount > 0 then 'topup' else 'adjustment' end,
     p_amount, v_bal,
     nullif(btrim(p_reference), ''),
     left(nullif(btrim(p_note), ''), 300),
     auth.uid());

  return v_bal;
end;
$$;

-- -------------------------------------------------------------------------------
-- 10. Row Level Security
-- -----------------------------------------------------------------------------
alter table public.app_config          enable row level security;
alter table public.admin_roles         enable row level security;
alter table public.wallets             enable row level security;
alter table public.wallet_transactions enable row level security;
alter table public.rides               enable row level security;

-- app_config : lecture pour tout utilisateur connecté, écriture super admin.
drop policy if exists app_config_select on public.app_config;
create policy app_config_select on public.app_config
  for select to authenticated using (true);

drop policy if exists app_config_write on public.app_config;
create policy app_config_write on public.app_config
  for all to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());

-- admin_roles : lecture admin, écriture super admin.
drop policy if exists admin_roles_select on public.admin_roles;
create policy admin_roles_select on public.admin_roles
  for select to authenticated using (public.is_admin());

drop policy if exists admin_roles_write on public.admin_roles;
create policy admin_roles_write on public.admin_roles
  for all to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());

-- wallets : lecture par le propriétaire ou un admin. Aucune écriture directe.
drop policy if exists wallets_select on public.wallets;
create policy wallets_select on public.wallets
  for select to authenticated
  using (provider_id = (select auth.uid()) or public.is_admin());

-- wallet_transactions : même règle, lecture seule.
drop policy if exists wallet_tx_select on public.wallet_transactions;
create policy wallet_tx_select on public.wallet_transactions
  for select to authenticated
  using (provider_id = (select auth.uid()) or public.is_admin());

-- rides : lecture par les participants ou un admin.
drop policy if exists rides_select on public.rides;
create policy rides_select on public.rides
  for select to authenticated
  using (
    client_id = (select auth.uid())
    or provider_id = (select auth.uid())
    or public.is_admin()
  );

drop policy if exists rides_admin_update on public.rides;
create policy rides_admin_update on public.rides
  for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- profiles / providers : politiques minimales si aucune n'existe.
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'profiles') then
    execute 'alter table public.profiles enable row level security';
    execute 'create policy profiles_select_own on public.profiles
               for select to authenticated
               using (id = (select auth.uid()) or public.is_admin())';
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'providers') then
    execute 'alter table public.providers enable row level security';
    execute 'create policy providers_select_own on public.providers
               for select to authenticated
               using (id = (select auth.uid()) or public.is_admin())';
  end if;
end $$;

-- -------------------------------------------------------------------------------
-- 11. Droits d'exécution des RPC
-- -----------------------------------------------------------------------------
revoke all on function public.create_ride(text, double precision, double precision, double precision, double precision, integer, text, text, text) from public, anon;
revoke all on function public.ride_action(uuid, text, integer, text) from public, anon;
revoke all on function public.rides_nearby(double precision, double precision, numeric) from public, anon;
revoke all on function public.admin_credit_wallet(uuid, integer, text, text) from public, anon;

grant execute on function public.create_ride(text, double precision, double precision, double precision, double precision, integer, text, text, text) to authenticated;
grant execute on function public.ride_action(uuid, text, integer, text) to authenticated;
grant execute on function public.rides_nearby(double precision, double precision, numeric) to authenticated;
grant execute on function public.admin_credit_wallet(uuid, integer, text, text) to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_super_admin() to authenticated;

-- -------------------------------------------------------------------------------
-- 12. Realtime (suivi des courses et du wallet)
-- -----------------------------------------------------------------------------
do $$
begin
  begin
    alter publication supabase_realtime add table public.rides;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.wallets;
  exception when duplicate_object then null;
  end;
end $$;

commit;