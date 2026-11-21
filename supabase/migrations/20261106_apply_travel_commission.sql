-- =============================================================================
-- MONTOTEM : commission sur les frais de déplacement (kind = 'trajet')
-- 1. apply_travel_commission : débite le wallet du prestataire.
-- 2. confirm_mission_payment : l'appelle à la confirmation d'un paiement
--    de trajet.
-- Le blocage éventuel est géré par trg_wallets_auto_block (déjà en place).
-- =============================================================================
begin;

create or replace function public.apply_travel_commission(
  p_mission uuid,
  p_amount  integer,
  p_payment uuid
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_provider   uuid;
  v_pct        integer;
  v_commission integer;
  v_balance    integer;
  v_ref        text := 'trajet:' || p_payment::text;
begin
  if p_amount is null or p_amount <= 0 then
    return 0;
  end if;

  select m.provider_id into v_provider
    from public.missions m
   where m.id = p_mission;
  if not found then
    raise exception 'INTROUVABLE' using errcode = 'P0002';
  end if;

  select coalesce((select c.value_int
                     from public.app_config c
                    where c.key = 'commission_travel_pct'), 15)
    into v_pct;
  v_pct := greatest(0, least(100, v_pct));

  v_commission := round(p_amount * v_pct / 100.0)::integer;
  if v_commission <= 0 then
    return 0;
  end if;

  -- Idempotence : un paiement ne peut être commissionné qu'une fois.
  if exists (select 1 from public.wallet_transactions t where t.reference = v_ref) then
    return 0;
  end if;

  -- Le wallet peut ne pas exister encore (prestataire sans mouvement).
  insert into public.wallets (provider_id, balance_fcfa)
  values (v_provider, -v_commission)
  on conflict (provider_id) do update
     set balance_fcfa = public.wallets.balance_fcfa - v_commission,
         updated_at   = now()
  returning balance_fcfa into v_balance;

  insert into public.wallet_transactions
    (provider_id, kind, amount_fcfa, balance_after, reference, note)
  values
    (v_provider, 'commission_travel', -v_commission, v_balance, v_ref,
     'Déplacement ' || p_amount || ' FCFA · ' || v_pct || ' %');

  return v_commission;
end;
$$;

-- Fonction interne : jamais appelable directement par un client.
revoke all on function public.apply_travel_commission(uuid, integer, uuid)
  from public, anon, authenticated;

create or replace function public.confirm_mission_payment(p_payment uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_p   public.mission_payments%rowtype;
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  select mp.* into v_p from public.mission_payments mp
    join public.missions m on m.id = mp.mission_id
   where mp.id = p_payment and m.provider_id = v_uid and mp.confirmed_at is null for update of mp;
  if not found then raise exception 'INTROUVABLE' using errcode = 'P0002'; end if;
  update public.mission_payments set confirmed_at = now() where id = v_p.id;
  update public.missions set paid_fcfa = paid_fcfa + v_p.amount_fcfa where id = v_p.mission_id;

  if v_p.kind = 'trajet' then
    perform public.apply_travel_commission(v_p.mission_id, v_p.amount_fcfa, v_p.id);
  end if;

  perform public.log_mission_event(v_p.mission_id, 'payment_confirmed',
    jsonb_build_object('amount_fcfa', v_p.amount_fcfa));
end;
$$;

commit;