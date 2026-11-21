-- =============================================================================
-- 035 — Paiements mission : declare/confirm/reject + apply_travel_commission
-- Dart : mission_service.dart, mission_payments_card.dart
-- Dépend de : 016, 019, 039
-- =============================================================================
begin;

set local search_path to public, extensions;

-- Déclaration client
create or replace function public.declare_mission_payment(
  p_mission   uuid, p_kind text, p_operateur text,
  p_phone     text default null, p_ref text default null
) returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid    uuid := auth.uid();
  m        public.missions%rowtype;
  v_amount integer;
  v_phone  text := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
  v_ref    text := upper(btrim(coalesce(p_ref, '')));
  v_op_pro text;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  select * into m from public.missions where id = p_mission and client_id = v_uid for update;
  if not found then raise exception 'INTROUVABLE' using errcode = 'P0002'; end if;
  if p_kind not in ('trajet','reparation') then
    raise exception 'RIEN_A_PAYER' using errcode = '22023';
  end if;
  if p_operateur not in ('mtn','moov','celtiis','especes') then
    raise exception 'OPERATEUR_INVALIDE' using errcode = '22023';
  end if;

  if p_kind = 'trajet' then
    if m.status <> 'pending' or p_operateur = 'especes' then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    v_amount := m.travel_fee_fcfa;
  else
    if m.status not in ('completed','working') then
      raise exception 'STATUT_INVALIDE' using errcode = 'P0001';
    end if;
    v_amount := m.repair_fee_fcfa;
  end if;
  if v_amount is null or v_amount <= 0 then
    raise exception 'RIEN_A_PAYER' using errcode = 'P0001';
  end if;

  if exists (select 1 from public.mission_payments
              where mission_id = m.id and kind = p_kind and rejected_at is null) then
    raise exception 'DEJA_DECLARE' using errcode = 'P0001';
  end if;

  if p_operateur <> 'especes' then
    select momo_operateur into v_op_pro from public.providers where id = m.provider_id;
    if v_op_pro is null then
      raise exception 'OPERATEUR_INVALIDE' using errcode = 'P0001';
    end if;
    if char_length(v_phone) < 8 then
      raise exception 'TELEPHONE_INVALIDE' using errcode = '22023';
    end if;
    if char_length(v_ref) < 4 then
      raise exception 'REFERENCE_INVALIDE' using errcode = '22023';
    end if;
    if exists (select 1 from public.mission_payments
                where upper(reference) = v_ref and rejected_at is null) then
      raise exception 'REFERENCE_DEJA_UTILISEE' using errcode = 'P0001';
    end if;
  end if;

  insert into public.mission_payments
    (mission_id, kind, amount_fcfa, operateur, payer_phone, reference)
  values
    (m.id, p_kind, v_amount, p_operateur, nullif(v_phone,''), nullif(v_ref,''));

  perform public.log_mission_event(m.id, 'payment_declared',
    jsonb_build_object('kind', p_kind, 'amount', v_amount, 'operateur', p_operateur));
end;
$$;
revoke all on function public.declare_mission_payment(uuid, text, text, text, text)
  from public, anon;
grant execute on function public.declare_mission_payment(uuid, text, text, text, text)
  to authenticated;

-- Confirmation prestataire
create or replace function public.confirm_mission_payment(p_payment uuid)
returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_p   public.mission_payments%rowtype;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  select mp.* into v_p from public.mission_payments mp
    join public.missions m on m.id = mp.mission_id
   where mp.id = p_payment and m.provider_id = v_uid
     and mp.confirmed_at is null and mp.rejected_at is null
   for update of mp;
  if not found then raise exception 'INTROUVABLE' using errcode = 'P0002'; end if;
  update public.mission_payments set confirmed_at = now() where id = v_p.id;
  update public.missions set paid_fcfa = paid_fcfa + v_p.amount_fcfa
   where id = v_p.mission_id;
  if v_p.kind = 'trajet' then
    perform public.apply_travel_commission(v_p.mission_id, v_p.amount_fcfa, v_p.id);
  end if;
  perform public.log_mission_event(v_p.mission_id, 'payment_confirmed',
    jsonb_build_object('amount_fcfa', v_p.amount_fcfa));
end;
$$;
revoke all on function public.confirm_mission_payment(uuid) from public, anon;
grant execute on function public.confirm_mission_payment(uuid) to authenticated;

-- Refus prestataire
create or replace function public.reject_mission_payment(
  p_payment uuid, p_reason text
) returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid    uuid := auth.uid();
  v_reason text := left(nullif(btrim(p_reason), ''), 300);
  v_p      public.mission_payments%rowtype;
  m        public.missions%rowtype;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  if v_reason is null then
    raise exception 'MOTIF_OBLIGATOIRE' using errcode = '22023';
  end if;
  select * into v_p from public.mission_payments where id = p_payment for update;
  if not found then raise exception 'INTROUVABLE' using errcode = 'P0002'; end if;
  select * into m from public.missions where id = v_p.mission_id;
  if not found or m.provider_id <> v_uid then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;
  if v_p.confirmed_at is not null or v_p.rejected_at is not null then
    raise exception 'DEJA_TRAITEE' using errcode = 'P0001';
  end if;
  update public.mission_payments
     set rejected_at = now(), reject_reason = v_reason
   where id = v_p.id;
  perform public.safe_notify(m.client_id, 'payment_rejected',
    'Paiement refusé', 'Motif : ' || v_reason,
    jsonb_build_object('mission_id', m.id, 'payment_id', v_p.id));
end;
$$;
revoke all on function public.reject_mission_payment(uuid, text) from public, anon;
grant execute on function public.reject_mission_payment(uuid, text) to authenticated;

commit;