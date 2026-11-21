-- =============================================================================
-- MONTOTEM : Script 12 - Stockage (RLS complète), push asynchrone, Realtime admin
-- Fichier  : sql/12_storage_push_realtime.sql
-- Prérequis : scripts 01b, 04b, 05, 07, 08, 09, 10, 11 exécutés. Idempotent.
-- =============================================================================
begin;

set local search_path to public, extensions;

-- -----------------------------------------------------------------------------
-- 1. Stockage : le chemin doit commencer par <uid>/..., providers/<uid>/...
--    ou clients/<uid>/..., où <uid> est STRICTEMENT auth.uid().
-- -----------------------------------------------------------------------------
create or replace function public.storage_owner_ok(p_name text)
returns boolean
language sql
stable
as $$
  select auth.uid() is not null
     and coalesce(cardinality(storage.foldername(p_name)), 0) >= 1
     and (
       (storage.foldername(p_name))[1] = auth.uid()::text
       or (
         (storage.foldername(p_name))[1] in ('providers', 'clients')
         and (storage.foldername(p_name))[2] = auth.uid()::text
       )
     );
$$;

drop policy if exists storage_avatars_insert   on storage.objects;
drop policy if exists storage_avatars_delete   on storage.objects;
drop policy if exists storage_documents_insert on storage.objects;
drop policy if exists storage_documents_select on storage.objects;
drop policy if exists storage_documents_delete on storage.objects;
drop policy if exists storage_avatars_select   on storage.objects;
drop policy if exists storage_avatars_update   on storage.objects;
drop policy if exists storage_documents_update on storage.objects;

-- avatars (bucket public : la lecture par URL publique ne passe pas par la RLS ;
-- la politique SELECT sert au listage et à l'upsert par le propriétaire).
create policy storage_avatars_select on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars'
         and (public.storage_owner_ok(name) or public.is_admin()));

create policy storage_avatars_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and public.storage_owner_ok(name));

create policy storage_avatars_update on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and public.storage_owner_ok(name))
  with check (bucket_id = 'avatars' and public.storage_owner_ok(name));

create policy storage_avatars_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and public.storage_owner_ok(name));

-- documents (bucket privé : pièces d'identité, accès par URL signée).
create policy storage_documents_select on storage.objects
  for select to authenticated
  using (bucket_id = 'documents'
         and (public.storage_owner_ok(name) or public.is_admin()));

create policy storage_documents_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'documents' and public.storage_owner_ok(name));

create policy storage_documents_update on storage.objects
  for update to authenticated
  using (bucket_id = 'documents' and public.storage_owner_ok(name))
  with check (bucket_id = 'documents' and public.storage_owner_ok(name));

create policy storage_documents_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'documents' and public.storage_owner_ok(name));

-- -----------------------------------------------------------------------------
-- 2. Push : un seul secret, INTERNAL_PUSH_SECRET, dans internal_settings.
--    Migration de l'ancienne clé push_webhook_secret si elle existe.
-- -----------------------------------------------------------------------------
create table if not exists public.internal_settings (
  key        text primary key,
  value      text not null,
  updated_at timestamptz not null default now()
);

alter table public.internal_settings enable row level security;
revoke all on public.internal_settings from anon, authenticated;

insert into public.internal_settings (key, value)
select 'INTERNAL_PUSH_SECRET', s.value
  from public.internal_settings s
 where s.key = 'push_webhook_secret'
on conflict (key) do nothing;

delete from public.internal_settings where key = 'push_webhook_secret';

create extension if not exists pg_net;

-- Appel asynchrone : pg_net met la requête en file et la transmet après le
-- COMMIT de la transaction métier. Aucune exception ne remonte jamais.
create or replace function public.notifications_push_dispatch()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_url    text;
  v_secret text;
begin
  select value into v_url    from public.internal_settings where key = 'push_function_url';
  select value into v_secret from public.internal_settings where key = 'INTERNAL_PUSH_SECRET';

  if coalesce(v_url, '') = '' or coalesce(v_secret, '') = '' then
    return new;
  end if;

  perform net.http_post(
    url     := v_url,
    body    := jsonb_build_object('notification_id', new.id),
    headers := jsonb_build_object(
                 'Content-Type',  'application/json',
                 'Authorization', 'Bearer ' || v_secret),
    timeout_milliseconds := 5000
  );
  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists trg_notifications_push on public.notifications;
create trigger trg_notifications_push
  after insert on public.notifications
  for each row execute function public.notifications_push_dispatch();

-- -----------------------------------------------------------------------------
-- 3. Realtime : suivi admin en direct (la RLS s'applique à chaque abonné)
-- -----------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['missions', 'providers', 'notifications',
                           'mission_payments', 'subscription_requests',
                           'provider_reports', 'rides', 'wallets']
  loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception
      when duplicate_object then null;
      when undefined_table  then null;
    end;
  end loop;
end $$;

commit;