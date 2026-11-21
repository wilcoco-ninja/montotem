-- =============================================================================
-- 058 — RPC earnings/revenue manquantes
-- admin_revenue_summary, provider_earnings_summary,
-- admin_commission_summary, admin_delete_commission_rule
-- =============================================================================
begin;
set local search_path to public, extensions;

-- 1. admin_revenue_summary
create or replace function public.admin_revenue_summary(p_days integer default 30)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_from timestamptz := now() - make_interval(days => v_days);
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'days', v_days,
    'commission_cash_fcfa', coalesce((
      select -sum(amount_fcfa) from public.wallet_transactions
       where kind = 'commission_cash' and created_at > v_from), 0),
    'commission_momo_fcfa', coalesce((
      select -sum(amount_fcfa) from public.wallet_transactions
       where kind = 'commission_momo' and created_at > v_from), 0),
    'commission_travel_fcfa', coalesce((
      select -sum(amount_fcfa) from public.wallet_transactions
       where kind = 'commission_travel' and created_at > v_from), 0),
    'commission_total_fcfa', coalesce((
      select -sum(amount_fcfa) from public.wallet_transactions
       where kind in ('commission_cash','commission_momo','commission_travel')
         and created_at > v_from), 0),
    'topups_fcfa', coalesce((
      select sum(amount_fcfa) from public.wallet_transactions
       where kind = 'topup' and created_at > v_from), 0),
    'rides_completed', coalesce((
      select count(*) from public.rides
       where status = 'completed' and completed_at > v_from), 0),
    'rides_volume_fcfa', coalesce((
      select sum(final_fare_fcfa) from public.rides
       where status = 'completed' and completed_at > v_from), 0),
    'wallet_debt_fcfa', coalesce((
      select sum(-balance_fcfa) from public.wallets where balance_fcfa < 0), 0),
    'providers_blocked', coalesce((
      select count(*) from public.wallets where blocked), 0),
    'series', coalesce((
      select jsonb_agg(jsonb_build_object(
        'day', to_char(d, 'YYYY-MM-DD'),
        'cash', coalesce(c, 0),
        'momo', coalesce(m, 0),
        'travel', coalesce(t, 0)) order by d)
        from (
          select g::date as d,
            (select coalesce(-sum(amount_fcfa), 0) from public.wallet_transactions
              where kind = 'commission_cash' and created_at::date = g::date) as c,
            (select coalesce(-sum(amount_fcfa), 0) from public.wallet_transactions
              where kind = 'commission_momo' and created_at::date = g::date) as m,
            (select coalesce(-sum(amount_fcfa), 0) from public.wallet_transactions
              where kind = 'commission_travel' and created_at::date = g::date) as t
          from generate_series(v_from::date, now()::date, interval '1 day') g
        ) x), '[]'::jsonb)
  );
end;
$$;
grant execute on function public.admin_revenue_summary(integer) to authenticated;

-- 2. provider_earnings_summary
create or replace function public.provider_earnings_summary(p_days integer default 30)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_from timestamptz := now() - make_interval(days => v_days);
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  if not exists (select 1 from public.providers where id = v_uid) then
    raise exception 'PAS_PRESTATAIRE' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'days', v_days,
    'rides_cash_count', coalesce((select count(*) from public.rides
      where provider_id = v_uid and status = 'completed'
        and payment_method = 'cash' and completed_at > v_from), 0),
    'rides_cash_fcfa', coalesce((select sum(final_fare_fcfa) from public.rides
      where provider_id = v_uid and status = 'completed'
        and payment_method = 'cash' and completed_at > v_from), 0),
    'rides_momo_count', coalesce((select count(*) from public.rides
      where provider_id = v_uid and status = 'completed'
        and payment_method <> 'cash' and completed_at > v_from), 0),
    'rides_momo_fcfa', coalesce((select sum(final_fare_fcfa) from public.rides
      where provider_id = v_uid and status = 'completed'
        and payment_method <> 'cash' and completed_at > v_from), 0),
    'travel_gross_fcfa', coalesce((select sum(travel_fee_fcfa) from public.missions
      where provider_id = v_uid and status = 'completed' and work_ended_at > v_from), 0),
    'repair_gross_fcfa', coalesce((select sum(repair_fee_fcfa) from public.missions
      where provider_id = v_uid and status = 'completed' and work_ended_at > v_from), 0),
    'gross_fcfa', coalesce((select sum(travel_fee_fcfa + repair_fee_fcfa)
      from public.missions where provider_id = v_uid and status = 'completed'
        and work_ended_at > v_from), 0),
    'commission_fcfa', coalesce((select -sum(amount_fcfa) from public.wallet_transactions
      where provider_id = v_uid
        and kind in ('commission_cash','commission_momo','commission_travel')
        and created_at > v_from), 0),
    'net_fcfa', coalesce((select sum(final_fare_fcfa) from public.rides
      where provider_id = v_uid and status = 'completed' and completed_at > v_from), 0)
      + coalesce((select sum(travel_fee_fcfa + repair_fee_fcfa) from public.missions
          where provider_id = v_uid and status = 'completed' and work_ended_at > v_from), 0)
      - coalesce((select -sum(amount_fcfa) from public.wallet_transactions
          where provider_id = v_uid
            and kind in ('commission_cash','commission_momo','commission_travel')
            and created_at > v_from), 0),
    'series', coalesce((
      select jsonb_agg(jsonb_build_object(
        'day', to_char(d, 'YYYY-MM-DD'),
        'gross', coalesce(g, 0),
        'commission', coalesce(c, 0)) order by d)
        from (
          select g2::date as d,
            coalesce((select sum(final_fare_fcfa) from public.rides
                       where provider_id = v_uid and status = 'completed'
                         and completed_at::date = g2::date), 0)
            + coalesce((select sum(travel_fee_fcfa + repair_fee_fcfa) from public.missions
                         where provider_id = v_uid and status = 'completed'
                           and work_ended_at::date = g2::date), 0) as g,
            coalesce((select -sum(amount_fcfa) from public.wallet_transactions
                       where provider_id = v_uid
                         and kind in ('commission_cash','commission_momo','commission_travel')
                         and created_at::date = g2::date), 0) as c
          from generate_series(v_from::date, now()::date, interval '1 day') g2
        ) x), '[]'::jsonb)
  );
end;
$$;
grant execute on function public.provider_earnings_summary(integer) to authenticated;

-- 3. admin_commission_summary
create or replace function public.admin_commission_summary()
returns jsonb language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'total_rules', (select count(*) from public.commission_rules where actif),
    'avg_pct', coalesce((select round(avg(pct), 2) from public.commission_rules where actif), 0),
    'by_category', coalesce((select jsonb_object_agg(service_category, jsonb_build_object(
        'pct', pct, 'provider_kind', provider_kind, 'vehicle_type', vehicle_type))
        from public.commission_rules where actif), '{}'::jsonb)
  );
end;
$$;
grant execute on function public.admin_commission_summary() to authenticated;

-- 4. admin_delete_commission_rule
create or replace function public.admin_delete_commission_rule(p_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;
  delete from public.commission_rules where id = p_id;
  if not found then raise exception 'INTROUVABLE' using errcode = 'P0002'; end if;
end;
$$;
grant execute on function public.admin_delete_commission_rule(uuid) to authenticated;

commit;