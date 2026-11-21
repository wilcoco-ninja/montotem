-- =============================================================================
-- 046 — Dispatch push HTTP asynchrone (pg_net)
-- Dart : push_service.dart (écoute le Realtime sur notifications)
-- Dépend de : 011
-- Note : le trigger envoie les notifications à une Edge Function configurée
--        dans internal_settings, sans bloquer la transaction.
-- =============================================================================
begin;

set local search_path to public, extensions;

create table if not exists public.internal_settings (
  key        text primary key,
  value      text not null,
  updated_at timestamptz not null default now()
);
alter table public.internal_settings enable row level security;
revoke all on public.internal_settings from anon, authenticated;

create or replace function public.notifications_push_dispatch()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_url    text;
  v_secret text;
begin
  select value into v_url    from public.internal_settings where key = 'push_function_url';
  select value into v_secret from public.internal_settings where key = 'INTERNAL_PUSH_SECRET';
  if coalesce(v_url,'') = '' or coalesce(v_secret,'') = '' then
    return new;
  end if;
  perform net.http_post(
    url := v_url,
    body := jsonb_build_object('notification_id', new.id),
    headers := jsonb_build_object(
                 'Content-Type','application/json',
                 'Authorization','Bearer ' || v_secret),
    timeout_milliseconds := 5000);
  return new;
exception when others then
  return new;
end;
$$;

drop trigger if exists trg_notifications_push on public.notifications;
create trigger trg_notifications_push
  after insert on public.notifications
  for each row execute function public.notifications_push_dispatch();

commit;