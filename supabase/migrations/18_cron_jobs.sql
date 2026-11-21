-- =============================================================================
-- MONTOTEM : Script 18 - Tâches planifiées (pg_cron) et rétention
-- =============================================================================
begin;

create extension if not exists pg_cron with schema pg_catalog;

-- 1. Expiration des missions dont le déplacement n'est pas payé (toutes les 2 min)
do $$
begin
  if to_regprocedure('public.expire_unpaid_missions()') is not null then
    perform cron.schedule(
      'montotem_expire_missions',
      '*/2 * * * *',
      'select public.expire_unpaid_missions();'
    );
  else
    raise notice 'expire_unpaid_missions() absente : exécutez 14_catalog_priced_missions.sql puis relancez ce script.';
  end if;
end;
$$;

-- 2. Rétention des notifications : lues > 60 jours, toutes > 180 jours
select cron.schedule(
  'montotem_purge_notifications',
  '30 3 * * *',
  $job$
    delete from public.notifications
     where created_at < now() - interval '180 days'
        or (read_at is not null and read_at < now() - interval '60 days');
  $job$
);

commit;

-- Vérification
select jobname, schedule, active
  from cron.job
 where jobname like 'montotem_%'
 order by jobname;