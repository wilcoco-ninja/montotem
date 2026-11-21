-- =============================================================================
-- 011 — Notifications (in-app + admin)
-- Dart : push_service.dart, admin_notification_service.dart,
--        admin_dashboard_screen.dart, admin_notifications_screen.dart
-- Dépend de : 010
-- =============================================================================
begin;

set local search_path to public, extensions;

-- Dart : AdminNotification.fromJson (type, title, body, payload, read_at)
create table if not exists public.notifications (
  id           uuid primary key default gen_random_uuid(),
  recipient_id uuid references auth.users(id) on delete cascade,
  admins_only  boolean not null default false,
  type         text not null,
  title        text not null,
  body         text,
  payload      jsonb not null default '{}'::jsonb,
  read_at      timestamptz,
  created_at   timestamptz not null default now()
);

create index if not exists idx_notifications_recipient
  on public.notifications (recipient_id, created_at desc);
create index if not exists idx_notifications_admins
  on public.notifications (created_at desc) where admins_only;

-- Dart : notify_user() et notify_admins() ne sont appelés qu'en interne
create or replace function public.notify_user(
  p_user uuid, p_type text, p_title text,
  p_body text default null, p_data jsonb default '{}'::jsonb
) returns void
language sql security definer set search_path = public
as $$
  insert into public.notifications
    (recipient_id, admins_only, type, title, body, payload)
  values
    (p_user, false, p_type, p_title, p_body, coalesce(p_data, '{}'::jsonb));
$$;

create or replace function public.notify_admins(
  p_type text, p_title text, p_body text default null, p_data jsonb default '{}'::jsonb
) returns void
language sql security definer set search_path = public
as $$
  insert into public.notifications
    (recipient_id, admins_only, type, title, body, payload)
  values
    (null, true, p_type, p_title, p_body, coalesce(p_data, '{}'::jsonb));
$$;

-- Wrappers jamais bloquants (utilisés par tous les triggers)
create or replace function public.safe_notify(
  p_user uuid, p_type text, p_title text,
  p_body text default null, p_data jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path = public
as $$
begin
  if p_user is null then return; end if;
  begin
    perform public.notify_user(p_user, p_type, p_title, p_body,
                               coalesce(p_data, '{}'::jsonb));
  exception when others then null; end;
end;
$$;

create or replace function public.safe_notify_admins(
  p_type text, p_title text, p_body text default null, p_data jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path = public
as $$
begin
  begin
    perform public.notify_admins(p_type, p_title, p_body,
                                 coalesce(p_data, '{}'::jsonb));
  exception when others then null; end;
end;
$$;

revoke all on function public.notify_user(uuid,text,text,text,jsonb)
  from public, anon, authenticated;
revoke all on function public.notify_admins(text,text,text,jsonb)
  from public, anon, authenticated;
revoke all on function public.safe_notify(uuid,text,text,text,jsonb)
  from public, anon, authenticated;
revoke all on function public.safe_notify_admins(text,text,text,jsonb)
  from public, anon, authenticated;

commit;