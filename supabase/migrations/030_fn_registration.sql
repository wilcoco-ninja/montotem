-- =============================================================================
-- 030 — RPC d'inscription prestataire
-- Dart : quick_auth_service.dart (registerProvider), auth_service.dart
-- Dépend de : 010, 013
-- =============================================================================
begin;

set local search_path to public, extensions;

create or replace function public.register_profile(
  p_role             text,
  p_first_name       text             default null,
  p_last_name        text             default null,
  p_email            text             default null,
  p_phone            text             default null,
  p_photo_profil_url text             default null,
  p_business_name    text             default null,
  p_metier           text             default null,
  p_ville            text             default null,
  p_ifu              text             default null,
  p_photo_cni_url    text             default null,
  p_latitude         double precision default null,
  p_longitude        double precision default null
) returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid         uuid := auth.uid();
  v_phone       text;
  v_email       text;
  v_prev        public.profiles%rowtype;
  v_has_prev    boolean;
  v_bn          text := nullif(btrim(p_business_name), '');
  v_metier      text := nullif(btrim(p_metier), '');
  v_new_provider boolean := false;
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;
  if p_role is null or p_role not in ('client','provider') then
    raise exception 'ROLE_INVALIDE' using errcode = '22023';
  end if;

  select * into v_prev from public.profiles where id = v_uid;
  v_has_prev := found;
  if v_has_prev and (v_prev.role = 'admin'
       or (v_prev.inscription_complete and v_prev.role <> p_role)) then
    raise exception 'ROLE_IMMUABLE' using errcode = 'P0001';
  end if;

  if p_role = 'provider' then
    if v_bn is null or v_metier is null then
      raise exception 'CHAMPS_OBLIGATOIRES' using errcode = '22023';
    end if;
    if p_latitude is null or p_longitude is null
       or p_latitude not between -90 and 90
       or p_longitude not between -180 and 180 then
      raise exception 'POSITION_OBLIGATOIRE' using errcode = '22023';
    end if;
    if nullif(btrim(p_photo_cni_url), '') is null then
      raise exception 'CNI_OBLIGATOIRE' using errcode = '22023';
    end if;
  end if;

  select case
    when u.phone is null or u.phone = '' then null
    when left(u.phone, 1) = '+' then u.phone
    else '+' || u.phone end,
    nullif(u.email, '')
    into v_phone, v_email
    from auth.users u where u.id = v_uid;

  insert into public.profiles
    (id, role, first_name, last_name, phone, email, photo_profil_url,
     inscription_complete)
  values
    (v_uid, p_role,
     left(nullif(btrim(p_first_name), ''), 80),
     left(nullif(btrim(p_last_name), ''), 80),
     v_phone,
     coalesce(v_email, nullif(btrim(p_email), '')),
     nullif(btrim(p_photo_profil_url), ''),
     true)
  on conflict (id) do update set
    role                 = excluded.role,
    first_name           = coalesce(excluded.first_name,       public.profiles.first_name),
    last_name            = coalesce(excluded.last_name,        public.profiles.last_name),
    phone                = coalesce(excluded.phone,            public.profiles.phone),
    email                = coalesce(excluded.email,            public.profiles.email),
    photo_profil_url     = coalesce(excluded.photo_profil_url, public.profiles.photo_profil_url),
    inscription_complete = true,
    updated_at           = now();

  if p_role = 'provider' then
    v_new_provider := not exists (select 1 from public.providers where id = v_uid);

    insert into public.providers
      (id, business_name, metier, ville, ifu, photo_cni_url, latitude, longitude)
    values
      (v_uid, left(v_bn, 120), left(v_metier, 80),
       left(nullif(btrim(p_ville), ''), 300),
       left(nullif(btrim(p_ifu), ''), 40),
       btrim(p_photo_cni_url), p_latitude, p_longitude)
    on conflict (id) do update set
      business_name = excluded.business_name,
      metier        = excluded.metier,
      ville         = coalesce(excluded.ville, public.providers.ville),
      ifu           = coalesce(excluded.ifu,   public.providers.ifu),
      photo_cni_url = excluded.photo_cni_url,
      latitude      = excluded.latitude,
      longitude     = excluded.longitude,
      statut_validation = case when public.providers.statut_validation = 'rejected'
                               then 'pending' else public.providers.statut_validation end,
      rejection_reason  = case when public.providers.statut_validation = 'rejected'
                               then null else public.providers.rejection_reason end,
      updated_at    = now();

    if v_new_provider then
      begin
        perform public.safe_notify_admins(
          'provider_registration',
          'Nouveau dossier prestataire',
          v_bn || ' (' || v_metier || ')',
          jsonb_build_object('provider_id', v_uid));
      exception when others then null;
      end;
    end if;
  end if;
end;
$$;

revoke all on function public.register_profile(
  text,text,text,text,text,text,text,text,text,text,text,double precision,double precision)
  from public, anon;
grant execute on function public.register_profile(
  text,text,text,text,text,text,text,text,text,text,text,double precision,double precision)
  to authenticated;

commit;