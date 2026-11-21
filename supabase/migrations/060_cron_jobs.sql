-- =============================================================================
-- 060 — Jobs planifiés (pg_cron)
-- Dart : (aucun — automatisation serveur)
-- Dépend de : 016, 011
-- =============================================================================
begin;

-- Expiration des missions non payées
create or replace function public.expire_unpaid_missions(p_minutes integer default 20)
returns integer
language plpgsql security definer set search_path = public, extensions
as $$
declare v_n integer;
begin
  with x as (
    update public.missions m
       set status = 'cancelled', cancelled_at = now(),
           cancel_reason = 'Frais de déplacement non payés à temps'
     where m.status = 'pending' and m.travel_fee_fcfa > 0
       and m.created_at < now() - make_interval(mins => greatest(p_minutes, 1))
       and not exists (select 1 from public.mission_payments pay
                        where pay.mission_id = m.id and pay.kind = 'trajet'
                          and pay.rejected_at is null)
    returning 1)
  select count(*) into v_n from x;
  return v_n;
end;
$$;
revoke all on function public.expire_unpaid_missions(integer)
  from public, anon, authenticated;

-- Rétention notifications
create or replace function public.purge_old_notifications()
returns integer
language sql security definer set search_path = public
as $$
  with x as (
    delete from public.notifications
     where created_at < now() - interval '180 days'
        or (read_at is not null and read_at < now() - interval '60 days')
    returning 1)
  select count(*) from x;
$$;

-- Programmation idempotente
do $$
declare r record;
begin
  for r in select jobid from cron.job
    where jobname in ('montotem_expire_missions','montotem_purge_notifications')
  loop
    perform cron.unschedule(r.jobid);
  end loop;
  perform cron.schedule('montotem_expire_missions', '*/2 * * * *',
    'select public.expire_unpaid_missions();');
  perform cron.schedule('montotem_purge_notifications', '30 3 * * *',
    'select public.purge_old_notifications();');
end $$;

commit;