-- =============================================================================
-- 039 — Application des commissions (courses + déplacements) + blocage wallet
-- Dart : (aucun direct — déclenché par triggers et confirm_mission_payment)
-- Dépend de : 019, 015, 017, 016
-- =============================================================================
begin;

set local search_path to public, extensions;

-- Commission course (trigger)
create or replace function public.rides_apply_commission()
returns trigger language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_pct  numeric;
  v_comm integer;
  v_bal  integer;
begin
  new.completed_at    := coalesce(new.completed_at, now());
  new.final_fare_fcfa := coalesce(new.final_fare_fcfa, new.fare_fcfa);
  if new.commission_applied or new.provider_id is null then return new; end if;

  v_pct  := public.commission_pct('ride_' || new.service_kind, new.service_kind, null);
  v_comm := round(new.final_fare_fcfa * v_pct / 100.0)::integer;

  if v_comm > 0 then
    insert into public.wallets (provider_id) values (new.provider_id)
      on conflict do nothing;
    update public.wallets
       set balance_fcfa = balance_fcfa - v_comm, updated_at = now()
     where provider_id = new.provider_id
    returning balance_fcfa into v_bal;
    insert into public.wallet_transactions
      (provider_id, ride_id, kind, amount_fcfa, balance_after, reference, note)
    values
      (new.provider_id, new.id,
       case when new.payment_method = 'cash' then 'commission_cash'
            else 'commission_momo' end,
       -v_comm, v_bal, 'course:' || new.id::text,
       'Commission ' || v_pct || ' % (' || new.service_kind || ')');
  end if;

  new.commission_fcfa    := v_comm;
  new.commission_pct     := v_pct;
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

-- Commission déplacement (appelée par confirm_mission_payment)
create or replace function public.apply_travel_commission(
  p_mission uuid, p_amount integer, p_payment uuid
) returns integer
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_provider uuid;
  v_kind     text;
  v_vehicle  text;
  v_cat      text;
  v_pct      numeric;
  v_comm     integer;
  v_bal      integer;
  v_ref      text := 'trajet:' || p_payment::text;
begin
  if p_amount is null or p_amount <= 0 then return 0; end if;

  select m.provider_id, m.vehicle_type, pv.provider_kind
    into v_provider, v_vehicle, v_kind
    from public.missions m
    join public.providers pv on pv.id = m.provider_id
   where m.id = p_mission;
  if not found then raise exception 'INTROUVABLE' using errcode = 'P0002'; end if;

  if v_kind = 'garage' and v_vehicle in ('voiture','camion','bus') then
    v_cat := 'mission_remorquage';
  else
    v_cat := 'mission_' || v_vehicle;
  end if;

  v_pct := public.commission_pct(v_cat, v_kind, v_vehicle);
  v_comm := round(p_amount * v_pct / 100.0)::integer;
  if v_comm <= 0 then return 0; end if;

  if exists (select 1 from public.wallet_transactions where reference = v_ref) then
    return 0;
  end if;

  insert into public.wallets (provider_id, balance_fcfa)
  values (v_provider, -v_comm)
  on conflict (provider_id) do update
     set balance_fcfa = public.wallets.balance_fcfa - v_comm, updated_at = now()
  returning balance_fcfa into v_bal;

  insert into public.wallet_transactions
    (provider_id, kind, amount_fcfa, balance_after, reference, note)
  values
    (v_provider, 'commission_travel', -v_comm, v_bal, v_ref,
     'Déplacement ' || p_amount || ' FCFA · ' || v_pct || ' % (' || v_cat || ')');

  return v_comm;
end;
$$;
revoke all on function public.apply_travel_commission(uuid, integer, uuid)
  from public, anon, authenticated;

-- Blocage wallet
create or replace function public.check_wallet_block(p_provider uuid)
returns boolean
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_threshold integer; v_bal integer; v_blocked boolean; v_reason text;
begin
  select value_int into v_threshold from public.app_config
   where key = 'wallet_block_threshold_fcfa';
  v_threshold := coalesce(v_threshold, 2000);
  select balance_fcfa, blocked, block_reason
    into v_bal, v_blocked, v_reason
    from public.wallets where provider_id = p_provider for update;
  if not found then return false; end if;
  if v_bal < -v_threshold then
    if not v_blocked then
      update public.wallets
         set blocked = true, blocked_at = now(),
             block_reason = 'solde_negatif', updated_at = now()
       where provider_id = p_provider;
    end if;
    return true;
  elsif v_blocked and v_reason = 'solde_negatif' then
    update public.wallets
       set blocked = false, blocked_at = null,
           block_reason = null, updated_at = now()
     where provider_id = p_provider;
    return false;
  end if;
  return v_blocked;
end;
$$;
revoke all on function public.check_wallet_block(uuid) from public, anon, authenticated;

commit;