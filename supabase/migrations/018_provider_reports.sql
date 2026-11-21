-- =============================================================================
-- 018 — Signalements
-- Dart : mission_service.dart (signaler), report_motifs.dart
-- Dépend de : 013, 016
-- =============================================================================
begin;

set local search_path to public, extensions;

create table if not exists public.provider_reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  provider_id uuid not null references public.providers(id) on delete cascade,
  mission_id  uuid references public.missions(id) on delete set null,
  motif       text not null,
  details     text,
  status      text not null default 'open'
              check (status in ('open','reviewing','resolved','dismissed')),
  admin_note  text,
  resolved_by uuid references public.profiles(id),
  resolved_at timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists idx_reports_status
  on public.provider_reports (status, created_at desc);
create index if not exists idx_reports_provider
  on public.provider_reports (provider_id, created_at desc);

commit;