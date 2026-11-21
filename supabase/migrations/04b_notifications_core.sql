-- =============================================================================
-- MONTOTEM : Script 04b - Notifications (table, notify_user, notify_admins, RLS)
-- =============================================================================
begin;

create table if not exists public.notifications (
  id           uuid primary key default gen_random_uuid(),
  recipient_id uuid references auth.users (id) on delete cascade,
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

create or replace function public.notify_user(
  p_user uuid, p_type text, p_title text, p_body text, p_data jsonb default '{}'::jsonb
) returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.notifications (recipient_id, admins_only, type, title, body, payload)
  values (p_user, false, p_type, p_title, p_body, coalesce(p_data, '{}'::jsonb));
$$;

create or replace function public.notify_admins(
  p_type text, p_title text, p_body text, p_data jsonb default '{}'::jsonb
) returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.notifications (recipient_id, admins_only, type, title, body, payload)
  values (null, true, p_type, p_title, p_body, coalesce(p_data, '{}'::jsonb));
$$;

revoke all on function public.notify_user(uuid, text, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.notify_admins(text, text, text, jsonb) from public, anon, authenticated;

alter table public.notifications enable row level security;

drop policy if exists notifications_select on public.notifications;
create policy notifications_select on public.notifications
  for select to authenticated
  using (
    recipient_id = (select auth.uid())
    or (admins_only and public.is_admin())
  );

drop policy if exists notifications_mark_read on public.notifications;
create policy notifications_mark_read on public.notifications
  for update to authenticated
  using (
    recipient_id = (select auth.uid())
    or (admins_only and public.is_admin())
  )
  with check (
    recipient_id = (select auth.uid())
    or (admins_only and public.is_admin())
  );

commit;