-- =============================================================================
-- MONTOTEM : Script 18 - Commission MoMo sur les courses + blocage wallet
-- =============================================================================
begin;

-- 1. Configuration (sans écraser les valeurs déjà présentes)
insert into public.app_config (key, value_int, note)
select v.key, v.value_int, v.note
from (values
  ('commission_momo_pct',        15,   'Commission MONTOTEM (%) sur les courses payées en Mobile Money'),
  ('commission_travel_pct',      15,   'Commission MONTOTEM (%) sur les frais de déplacement'),
  ('wallet_block_threshold_fcfa', 2000, 'Prestataire bloqué quand solde wallet < -seuil (FCFA)')
) as v(key, value_int, note)
where not exists (select 1 from public.app_config c where c.key = v.key);

-- 2. Contrainte CHECK sur wallet_transactions.kind : ajoute commission_momo si besoin
do $$
declare
  r     record;
  v_def text;
begin
  for r in
    select c.conname, pg_get_constraintdef(c.oid) as def
      from pg_constraint c
     where c.conrelid = 'public.wallet_transactions'::regclass
       and c.contype = 'c'
       and pg_get_constraintdef(c.oid) like '%commission_cash%'
       and pg_get_constraintdef(c.oid) not like '%commission_momo%'
  loop
    v_def := replace(
      r.def,
      '''commission_cash''::text',
      '''commission_cash''::text, ''commission_momo''::text'
    );
    execute format('alter table public.wallet_transactions drop constraint %I', r.conname);
    execute format('alter table public.wallet_transactions add constraint %I %s', r.conname, v_def);
  end loop;
end
$$;

-- 3. Une seule commission de course par course (créé seulement si aucun doublon existant)
do $$
begin
  if not exists (
    select 1
      from public.wallet_transactions t
     where t.kind in ('commission_cash', 'commission_momo')
       and t.ride_id is not null
     group by t.ride_id
    having count(*) > 1
  ) then
    create unique index if not exists uq_wallet_tx_ride_commission
      on public.wallet_transactions (ride_id)
      where kind in ('commission_cash', 'commission_momo');
  end if;
end
$$;

-- 4. Blocage automatique du prestataire (solde < -seuil)
create or replace function public.check_wallet_block(p_provider uuid)
returns boolean
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_threshold integer;
  v_bal       integer;
  v_blocked   boolean;
  v_reason    text;
begin
  select coalesce(
           (select c.value_int from public.app_config c
             where c.key = 'wallet_block_threshold_fcfa'), 2000)
    into v_threshold;

  select w.balance_fcfa, w.blocked, w.block_reason
    into v_bal, v_blocked, v_reason
    from public.wallets w
   where w.provider_id = p_provider
   for update;
  if not found then
    return false;
  end if;

  if v_bal < -v_threshold then
    if not v_blocked then
      update public.wallets
         set blocked = true, blocked_at = now(),
             block_reason = 'solde_negatif', updated_at = now()
       where provider_id = p_provider;
    end if;
    return true;
  elsif v_blocked and v_reason = 'solde_negatif' then
    -- Déblocage automatique uniquement pour un blocage posé par cette fonction.
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

-- 5. Commission sur TOUTES les courses (cash et Mobile Money)
create or replace function public.rides_apply_commission()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  v_pct   integer;
  v_base  integer;
  v_comm  integer;
  v_bal   integer;
  v_key   text;
  v_kind  text;
  v_label text;
begin
  new.completed_at    := coalesce(new.completed_at, now());
  new.final_fare_fcfa := coalesce(new.final_fare_fcfa, new.fare_fcfa);
  v_base := new.final_fare_fcfa;

  if new.commission_applied or new.provider_id is null then
    return new;
  end if;

  if new.payment_method = 'cash' then
    v_key   := 'commission_cash_pct';
    v_kind  := 'commission_cash';
    v_label := 'cash';
  else
    v_key   := 'commission_momo_pct';
    v_kind  := 'commission_momo';
    v_label := 'Mobile Money';
  end if;

  select c.value_int into v_pct
    from public.app_config c
   where c.key = v_key;
  v_pct  := greatest(0, least(100, coalesce(v_pct, 15)));
  v_comm := round(v_base * v_pct / 100.0)::integer;

  if v_comm > 0 then
    insert into public.wallets (provider_id) values (new.provider_id)
      on conflict do nothing;

    update public.wallets
       set balance_fcfa = balance_fcfa - v_comm,
           updated_at   = now()
     where provider_id = new.provider_id
    returning balance_fcfa into v_bal;

    insert into public.wallet_transactions
      (provider_id, ride_id, kind, amount_fcfa, balance_after, reference, note)
    values
      (new.provider_id, new.id, v_kind, -v_comm, v_bal, 'course:' || new.id::text,
       'Commission ' || v_pct || ' % sur course ' || v_label || ' de ' || v_base || ' FCFA');

    perform public.check_wallet_block(new.provider_id);
  end if;

  new.commission_fcfa    := v_comm;
  new.commission_applied := true;
  return new;
end;
$$;

-- 6. Commission déplacement : même fonction, ajout de check_wallet_block
create or replace function public.apply_travel_commission(p_mission uuid, p_amount integer, p_payment uuid)
returns integer
language plpgsql
security definer
set search_path to ''
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

  perform public.check_wallet_block(v_provider);

  return v_commission;
end;
$$;

commit;