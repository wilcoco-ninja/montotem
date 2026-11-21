create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('moto','voiture','camion')),
  plaque text, marque text, km_actuel int not null default 0,
  created_at timestamptz default now());
create table public.maintenance_rules (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  label text not null, every_km int, every_days int,
  last_km int not null default 0, last_date date not null default current_date);
alter table public.vehicles enable row level security;
alter table public.maintenance_rules enable row level security;
create policy v_own on public.vehicles for all to authenticated
  using (owner_id=(select auth.uid())) with check (owner_id=(select auth.uid()));
create policy m_own on public.maintenance_rules for all to authenticated
  using (exists(select 1 from public.vehicles v where v.id=vehicle_id and v.owner_id=(select auth.uid())));