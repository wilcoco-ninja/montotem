-- =============================================================================
-- MONTOTEM : Script 19 - Synthèses de gains (prestataire) et de revenus (admin)
-- Lecture seule. Jours calculés en heure du Bénin (UTC+1, sans heure d'été).
-- =============================================================================
begin;

create or replace function public.provider_earnings_summary(p_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public'
as $$
declare
  v_uid   uuid := auth.uid();
  v_days  integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_start timestamp := date_trunc('day', now() at time zone 'Africa/Lagos')
                       - make_interval(days => v_days - 1);
  v_rides_cash_n   integer;
  v_rides_cash     bigint;
  v_rides_momo_n   integer;
  v_rides_momo     bigint;
  v_rides_comm     bigint;
  v_travel_gross   bigint;
  v_repair_gross   bigint;
  v_travel_comm    bigint;
  v_balance        integer;
  v_blocked        boolean;
  v_series         jsonb;
begin
  if v_uid is null then
    raise exception 'NON_CONNECTE' using errcode = '28000';
  end if;
  if not exists (select 1 from public.providers pv where pv.id = v_uid) then
    raise exception 'PAS_PRESTATAIRE' using errcode = 'P0002';
  end if;

  select count(*) filter (where r.payment_method = 'cash'),
         coalesce(sum(r.final_fare_fcfa) filter (where r.payment_method = 'cash'), 0),
         count(*) filter (where r.payment_method <> 'cash'),
         coalesce(sum(r.final_fare_fcfa) filter (where r.payment_method <> 'cash'), 0),
         coalesce(sum(r.commission_fcfa), 0)
    into v_rides_cash_n, v_rides_cash, v_rides_momo_n, v_rides_momo, v_rides_comm
    from public.rides r
   where r.provider_id = v_uid
     and r.status = 'completed'
     and (r.completed_at at time zone 'Africa/Lagos') >= v_start;

  select coalesce(sum(mp.amount_fcfa) filter (where mp.kind = 'trajet'), 0),
         coalesce(sum(mp.amount_fcfa) filter (where mp.kind = 'reparation'), 0)
    into v_travel_gross, v_repair_gross
    from public.mission_payments mp
    join public.missions m on m.id = mp.mission_id
   where m.provider_id = v_uid
     and mp.confirmed_at is not null
     and (mp.confirmed_at at time zone 'Africa/Lagos') >= v_start;

  select coalesce(-sum(t.amount_fcfa), 0)
    into v_travel_comm
    from public.wallet_transactions t
   where t.provider_id = v_uid
     and t.kind = 'commission_travel'
     and (t.created_at at time zone 'Africa/Lagos') >= v_start;

  select coalesce(w.balance_fcfa, 0), coalesce(w.blocked, false)
    into v_balance, v_blocked
    from (select 1) x
    left join public.wallets w on w.provider_id = v_uid;

  select coalesce(jsonb_agg(jsonb_build_object(
           'day', to_char(d, 'YYYY-MM-DD'),
           'gross', g.gross,
           'commission', g.commission
         ) order by d), '[]'::jsonb)
    into v_series
    from generate_series(v_start, v_start + make_interval(days => v_days - 1), interval '1 day') d
    cross join lateral (
      select
        (select coalesce(sum(r.final_fare_fcfa), 0)
           from public.rides r
          where r.provider_id = v_uid and r.status = 'completed'
            and (r.completed_at at time zone 'Africa/Lagos') >= d
            and (r.completed_at at time zone 'Africa/Lagos') < d + interval '1 day')
        +
        (select coalesce(sum(mp.amount_fcfa), 0)
           from public.mission_payments mp
           join public.missions m on m.id = mp.mission_id
          where m.provider_id = v_uid and mp.confirmed_at is not null
            and (mp.confirmed_at at time zone 'Africa/Lagos') >= d
            and (mp.confirmed_at at time zone 'Africa/Lagos') < d + interval '1 day') as gross,
        (select coalesce(-sum(t.amount_fcfa), 0)
           from public.wallet_transactions t
          where t.provider_id = v_uid and t.kind like 'commission\_%'
            and (t.created_at at time zone 'Africa/Lagos') >= d
            and (t.created_at at time zone 'Africa/Lagos') < d + interval '1 day') as commission
    ) g;

  return jsonb_build_object(
    'days',                 v_days,
    'rides_cash_count',     v_rides_cash_n,
    'rides_cash_fcfa',      v_rides_cash,
    'rides_momo_count',     v_rides_momo_n,
    'rides_momo_fcfa',      v_rides_momo,
    'rides_commission_fcfa', v_rides_comm,
    'travel_gross_fcfa',    v_travel_gross,
    'travel_commission_fcfa', v_travel_comm,
    'repair_gross_fcfa',    v_repair_gross,
    'gross_fcfa',           v_rides_cash + v_rides_momo + v_travel_gross + v_repair_gross,
    'commission_fcfa',      v_rides_comm + v_travel_comm,
    'net_fcfa',             v_rides_cash + v_rides_momo + v_travel_gross + v_repair_gross
                            - v_rides_comm - v_travel_comm,
    'wallet_balance_fcfa',  v_balance,
    'wallet_blocked',       v_blocked,
    'series',               v_series
  );
end;
$$;

create or replace function public.admin_revenue_summary(p_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public'
as $$
declare
  v_days  integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_start timestamp := date_trunc('day', now() at time zone 'Africa/Lagos')
                       - make_interval(days => v_days - 1);
  v_cash    bigint;
  v_momo    bigint;
  v_travel  bigint;
  v_topups  bigint;
  v_rides_n integer;
  v_rides_v bigint;
  v_dette   bigint;
  v_bloques integer;
  v_series  jsonb;
begin
  if not public.is_admin() then
    raise exception 'INTERDIT' using errcode = '42501';
  end if;

  select coalesce(-sum(t.amount_fcfa) filter (where t.kind = 'commission_cash'), 0),
         coalesce(-sum(t.amount_fcfa) filter (where t.kind = 'commission_momo'), 0),
         coalesce(-sum(t.amount_fcfa) filter (where t.kind = 'commission_travel'), 0),
         coalesce(sum(t.amount_fcfa) filter (where t.kind = 'topup'), 0)
    into v_cash, v_momo, v_travel, v_topups
    from public.wallet_transactions t
   where (t.created_at at time zone 'Africa/Lagos') >= v_start;

  select count(*), coalesce(sum(r.final_fare_fcfa), 0)
    into v_rides_n, v_rides_v
    from public.rides r
   where r.status = 'completed'
     and (r.completed_at at time zone 'Africa/Lagos') >= v_start;

  select coalesce(sum(-w.balance_fcfa) filter (where w.balance_fcfa < 0), 0),
         count(*) filter (where w.blocked)
    into v_dette, v_bloques
    from public.wallets w;

  select coalesce(jsonb_agg(jsonb_build_object(
           'day', to_char(d, 'YYYY-MM-DD'),
           'cash', s.cash, 'momo', s.momo, 'travel', s.travel
         ) order by d), '[]'::jsonb)
    into v_series
    from generate_series(v_start, v_start + make_interval(days => v_days - 1), interval '1 day') d
    cross join lateral (
      select coalesce(-sum(t.amount_fcfa) filter (where t.kind = 'commission_cash'), 0)   as cash,
             coalesce(-sum(t.amount_fcfa) filter (where t.kind = 'commission_momo'), 0)   as momo,
             coalesce(-sum(t.amount_fcfa) filter (where t.kind = 'commission_travel'), 0) as travel
        from public.wallet_transactions t
       where (t.created_at at time zone 'Africa/Lagos') >= d
         and (t.created_at at time zone 'Africa/Lagos') < d + interval '1 day'
    ) s;

  return jsonb_build_object(
    'days',                    v_days,
    'commission_cash_fcfa',    v_cash,
    'commission_momo_fcfa',    v_momo,
    'commission_travel_fcfa',  v_travel,
    'commission_total_fcfa',   v_cash + v_momo + v_travel,
    'topups_fcfa',             v_topups,
    'rides_completed',         v_rides_n,
    'rides_volume_fcfa',       v_rides_v,
    'wallet_debt_fcfa',        v_dette,
    'providers_blocked',       v_bloques,
    'series',                  v_series
  );
end;
$$;

revoke all on function public.provider_earnings_summary(integer) from public, anon;
revoke all on function public.admin_revenue_summary(integer) from public, anon;
grant execute on function public.provider_earnings_summary(integer) to authenticated;
grant execute on function public.admin_revenue_summary(integer) to authenticated;

commit;