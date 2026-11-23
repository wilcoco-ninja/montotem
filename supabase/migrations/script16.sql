-- =============================================================================
-- MONTOTEM : Script 16 - Verification de fin de course par code a 6 chiffres
-- Fichier  : sql/16_verify_fin_course.sql
-- Prerequis : scripts 01b a 15 executes. Idempotent. Non destructif.
-- Principe :
--   1) Le conducteur saisit "Terminer la course" (prix final) -> la course
--      passe en statut 'verifying' et un code a 6 chiffres est genere.
--   2) Le code n'est lisible QUE par le client (masquage dans ride_build_json),
--      via une table separee ride_otp inaccessible en direct (RLS fermee).
--   3) Le client transmet le code au conducteur ; le conducteur le saisit
--      (RPC ride_confirm_otp) -> la course passe en 'completed', c'est
--      uniquement a ce moment que la commission est debitee du wallet
--      (trigger trg_rides_apply_commission : new.status = 'completed').
--   4) Code expire (15 min) ou epuise (5 essais) : le conducteur relance
--      "Terminer la course" -> nouveau code. Annulation interdite en
--      verifying : la fin doit passer par le code ou l'admin.
-- =============================================================================

begin;

set local search_path to public, extensions;

-- -----------------------------------------------------------------------------
-- 1. Table du code de fin de course (aucune policy : secrets, acces via RPC)
-- -----------------------------------------------------------------------------
create table if not exists public.ride_otp (
  ride_id    uuid primary key references public.rides(id) on delete cascade,
  code       text not null,
  expires_at timestamptz not null,
  attempts   integer not null default 0,
  updated_at timestamptz not null default now()
);

create index if not exists idx_ride_otp_expires
  on public.ride_otp (expires_at);

alter table public.ride_otp enable row level security;
revoke all on public.ride_otp from anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2. Statut 'verifying' autorise dans la contrainte de la table rides
-- -----------------------------------------------------------------------------
do $$
declare
  c record;
begin
  for c in
    select conname, pg_get_constraintdef(oid) as def
      from pg_constraint
     where conrelid = 'public.rides'::regclass
       and contype = 'c'
       and pg_get_constraintdef(oid) ilike '%status%'
  loop
    if position('verifying' in c.def) = 0 then
      execute format('alter table public.rides drop constraint %I', c.conname);
      execute format($f$
        alter table public.rides add constraint %I check (status in
          ('requested','accepted','arrived','in_progress','verifying',
           'completed','cancelled')) $f$, c.conname);
    end if;
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- 3. ride_action : complete -> verifying + code ; completions suivantes ->
--    nouveau code ; annulation refusee en verifying
-- -----------------------------------------------------------------------------
create or replace function public.ride_action(
  p_ride   uuid,
  p_action text,
  p_fare   integer default null,
  p_reason text    default null
) returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid   uuid := auth.uid();
  v_r     public.rides%rowtype;
  v_pv    public.providers%rowtype;
  v_dist  double precision;
  v_final integer;
  v_other uuid;
  v_code  text;
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

    -- Course payee en Mobile Money : le conducteur doit pouvoir etre paye.
    if v_r.payment_method <> 'cash'
       and (v_pv.momo_numero is null
            or v_pv.momo_operateur is distinct from v_r.payment_method) then
      raise exception 'MOMO_NON_CONFIGURE' using errcode = 'P0001';
    end if;

    -- Les gardes " wallet bloque " et " compte suspendu " sont portees par le
    -- trigger trg_rides_guard_blocked.
    update public.rides
       set provider_id = v_uid, status = 'accepted', accepted_at = now()
     where id = v_r.id;

    perform public.safe_notify(v_r.client_id, 'ride_accepted', 'Conducteur en route',
      'Votre course a ete acceptee. Suivez son arrivee en direct.',
      jsonb_build_object('ride_id', v_r.id));
    return 'accepted';

  elsif p_action in ('arrived', 'start', 'complete') then
    if v_r.provider_id is distinct from v_uid then
      raise exception 'INTERDIT' using errcode = '42501';
    end if;

    if p_action = 'arrived' then
      if v_r.status <> 'accepted' then
        raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
      end if;
      if v_r.provider_lat is null or v_r.provider_lng is null
         or v_r.provider_pos_at is null
         or v_r.provider_pos_at < now() - interval '5 minutes' then
        raise exception 'POSITION_INCONNUE' using errcode = 'P0001';
      end if;
      v_dist := st_distance(
        st_setsrid(st_makepoint(v_r.provider_lng, v_r.provider_lat), 4326)::geography,
        v_r.pickup);
      if v_dist > 500 then
        raise exception 'TROP_LOIN' using errcode = 'P0001';
      end if;

      update public.rides set status = 'arrived', arrived_at = now() where id = v_r.id;
      perform public.safe_notify(v_r.client_id, 'ride_arrived', 'Conducteur arrive',
        'Votre conducteur est sur place.', jsonb_build_object('ride_id', v_r.id));
      return 'arrived';

    elsif p_action = 'start' then
      if v_r.status <> 'arrived' then
        raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
      end if;
      update public.rides set status = 'in_progress', started_at = now() where id = v_r.id;
      perform public.safe_notify(v_r.client_id, 'ride_started', 'Course demarree',
        'Bonne route !', jsonb_build_object('ride_id', v_r.id));
      return 'in_progress';

    else
      -- 1re fin de course (depuis in_progress) ou regeneration du code
      -- (depuis verifying : code expire ou epuise).
      if v_r.status not in ('in_progress', 'verifying') then
        raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
      end if;

      -- Baisse libre ; hausse limitee a +50 % du prix convenu.
      v_final := coalesce(p_fare, v_r.fare_fcfa);
      if v_final < 100 or v_final > 500000 or v_final > (v_r.fare_fcfa * 3 / 2) then
        raise exception 'TARIF_INVALIDE' using errcode = '22023';
      end if;

      -- Code a 6 chiffres : lisible uniquement par le client dans
      -- ride_build_json (table ride_otp imprenable en direct).
      v_code := lpad(floor(random() * 1000000)::integer::text, 6, '0');

      update public.rides set status = 'verifying', final_fare_fcfa = v_final
       where id = v_r.id;

      insert into public.ride_otp (ride_id, code, expires_at, attempts)
      values (v_r.id, v_code, now() + interval '15 minutes', 0)
      on conflict (ride_id) do update
        set code = excluded.code,
            expires_at = excluded.expires_at,
            attempts = 0,
            updated_at = now();

      perform public.safe_notify(v_r.client_id, 'ride_completed', 'Fin de course',
        'Montant : ' || v_final || ' FCFA. Un code a 6 chiffres s''affiche : '
        'transmettez-le au conducteur pour finaliser.',
        jsonb_build_object('ride_id', v_r.id));
      return 'verifying';
    end if;

  elsif p_action = 'cancel' then
    if v_uid not in (v_r.client_id, coalesce(v_r.provider_id, v_r.client_id)) then
      raise exception 'INTERDIT' using errcode = '42501';
    end if;
    -- verifying : la fin passe par le code (ou l'admin).
    if v_r.status in ('completed', 'cancelled', 'in_progress', 'verifying') then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;

    update public.rides
       set status = 'cancelled', cancelled_at = now(), cancelled_by = v_uid,
           cancel_reason = left(nullif(btrim(p_reason), ''), 300)
     where id = v_r.id;

    v_other := case when v_uid = v_r.client_id then v_r.provider_id else v_r.client_id end;
    if v_other is not null then
      perform public.safe_notify(v_other, 'ride_cancelled', 'Course annulee',
        'La course a ete annulee.', jsonb_build_object('ride_id', v_r.id));
    end if;
    return 'cancelled';
  end if;

  raise exception 'ACTION_INVALIDE' using errcode = '22023';
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. Confirmation de la fin de course par le conducteur (code du client)
-- -----------------------------------------------------------------------------
create or replace function public.ride_confirm_otp(
  p_ride uuid,
  p_code text
) returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_r   public.rides%rowtype;
  v_otp public.ride_otp%rowtype;
  v_code text;
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;

  v_code := btrim(coalesce(p_code, ''));
  if v_code !~ '^[0-9]{6}$' then
    raise exception 'OTP_INVALIDE' using errcode = '22023';
  end if;

  select * into v_r from public.rides where id = p_ride for update;
  if not found or v_r.provider_id is distinct from v_uid then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;
  if v_r.status <> 'verifying' then
    raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
  end if;

  select * into v_otp from public.ride_otp where ride_id = v_r.id for update;
  if not found then
    raise exception 'OTP_INTROUVABLE' using errcode = 'P0002';
  end if;
  if v_otp.expires_at < now() then
    delete from public.ride_otp where ride_id = v_r.id;
    raise exception 'OTP_EXPIRE' using errcode = 'P0001';
  end if;
  if v_otp.attempts >= 5 then
    delete from public.ride_otp where ride_id = v_r.id;
    raise exception 'OTP_EPUISE' using errcode = 'P0001';
  end if;
  if v_otp.code <> v_code then
    update public.ride_otp
       set attempts = attempts + 1, updated_at = now()
     where ride_id = v_r.id;
    raise exception 'OTP_INVALIDE' using errcode = 'P0001';
  end if;

  -- Bascule completed : le trigger trg_rides_apply_commission debite ici,
  -- et uniquement ici, la commission du wallet du conducteur.
  update public.rides
     set status = 'completed', completed_at = now()
   where id = v_r.id;

  delete from public.ride_otp where ride_id = v_r.id;

  perform public.safe_notify(v_r.client_id, 'ride_completed', 'Course terminee',
    'Montant : ' || v_r.final_fare_fcfa || ' FCFA. Merci de votre fidelite.',
    jsonb_build_object('ride_id', v_r.id));
  return 'completed';
end;
$$;

-- -----------------------------------------------------------------------------
-- 5. ride_build_json : le code est expose au client (et a l'admin) uniquement
--    pendant la verification, et uniquement s'il est valide
-- -----------------------------------------------------------------------------
create or replace function public.ride_build_json(
  r        public.rides,
  p_viewer uuid,
  p_admin  boolean
) returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_reveal      boolean := p_admin or r.status in ('accepted', 'arrived', 'in_progress', 'completed');
  v_is_client   boolean := (p_viewer = r.client_id);
  v_is_provider boolean := (p_viewer = r.provider_id);
  v_cl    public.profiles%rowtype;
  v_pf    public.profiles%rowtype;
  v_pv    public.providers%rowtype;
  v_cname text;
  v_pname text;
  v_momo  jsonb := null;
  v_otp   public.ride_otp%rowtype;
  v_otp_code  text := null;
  v_otp_expires timestamptz := null;
begin
  select * into v_cl from public.profiles  where id = r.client_id;
  select * into v_pf from public.profiles  where id = r.provider_id;
  select * into v_pv from public.providers where id = r.provider_id;

  v_cname := coalesce(
    nullif(btrim(coalesce(v_cl.first_name, '') || ' ' || coalesce(v_cl.last_name, '')), ''),
    'Client');
  v_pname := coalesce(
    nullif(btrim(v_pv.business_name), ''),
    nullif(btrim(coalesce(v_pf.first_name, '') || ' ' || coalesce(v_pf.last_name, '')), ''),
    'Conducteur');

  -- Numero MoMo du conducteur : uniquement pour le client, apres acceptation,
  -- et seulement s'il correspond a l'operateur choisi.
  if v_reveal
     and r.payment_method <> 'cash'
     and v_pv.momo_numero is not null
     and v_pv.momo_operateur = r.payment_method
     and (p_admin or v_is_client) then
    v_momo := jsonb_build_object(
      'operateur', v_pv.momo_operateur,
      'numero',    v_pv.momo_numero,
      'titulaire', v_pv.momo_titulaire);
  end if;

  -- Code de fin de course : client (ou admin) uniquement, statut verifying.
  if r.status = 'verifying' and (p_admin or v_is_client) then
    select * into v_otp from public.ride_otp where ride_id = r.id;
    if found and v_otp.expires_at > now() then
      v_otp_code    := v_otp.code;
      v_otp_expires := v_otp.expires_at;
    end if;
  end if;

  return jsonb_build_object(
    'id',              r.id,
    'status',          r.status,
    'service_kind',    r.service_kind,
    'payment_method',  r.payment_method,
    'client_id',       r.client_id,
    'provider_id',     r.provider_id,
    'fare_fcfa',       r.fare_fcfa,
    'final_fare_fcfa', r.final_fare_fcfa,
    'commission_fcfa', case when p_admin or v_is_provider then r.commission_fcfa else null end,
    'distance_m',      r.distance_m,
    'pickup_lat',      st_y(r.pickup::geometry),
    'pickup_lng',      st_x(r.pickup::geometry),
    'dropoff_lat',     st_y(r.dropoff::geometry),
    'dropoff_lng',     st_x(r.dropoff::geometry),
    'pickup_address',  r.pickup_address,
    'dropoff_address', r.dropoff_address,
    'provider_lat',    r.provider_lat,
    'provider_lng',    r.provider_lng,
    'provider_pos_at', r.provider_pos_at,
    'accepted_at',     r.accepted_at,
    'arrived_at',      r.arrived_at,
    'started_at',      r.started_at,
    'completed_at',    r.completed_at,
    'cancelled_at',    r.cancelled_at,
    'cancel_reason',   r.cancel_reason,
    'otp_code',        v_otp_code,
    'otp_expires_at',  v_otp_expires,
    'created_at',      r.created_at,
    'client_name',     v_cname,
    'provider_name',   case when r.provider_id is null then null else v_pname end,
    'client_phone',    case when v_reveal and (p_admin or v_is_provider) then v_cl.phone else null end,
    'provider_phone',  case when v_reveal and (p_admin or v_is_client)   then v_pf.phone else null end,
    'provider_momo',   v_momo
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 6. Une seule course ouverte par client (statuts actifs + verifying) ;
--    les courses verifyes depuis plus de 2 h sont annulees automatiquement
-- -----------------------------------------------------------------------------
create or replace function public.rides_guard_one_active()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  update public.rides
     set status = 'cancelled', cancelled_at = now(),
         cancel_reason = 'Delai de confirmation depasse'
   where client_id = new.client_id
     and status = 'verifying'
     and started_at < now() - interval '2 hours';

  if exists (
    select 1 from public.rides r
     where r.client_id = new.client_id
       and r.status in ('requested', 'accepted', 'arrived', 'in_progress', 'verifying')
  ) then
    raise exception 'COURSE_EN_COURS' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_rides_one_active on public.rides;
create trigger trg_rides_one_active
  before insert on public.rides
  for each row
  execute function public.rides_guard_one_active();

-- -----------------------------------------------------------------------------
-- 7. Droits d'execution
-- -----------------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('ride_action', 'ride_confirm_otp')
  loop
    execute format('revoke all on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;

  for r in
    select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'ride_build_json'
  loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
end $$;

commit;