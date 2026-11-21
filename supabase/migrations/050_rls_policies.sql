-- =============================================================================
-- 050 — Row Level Security : toutes les policies
-- Dart : (sécurité — aucun appel direct)
-- Dépend de : 010 à 019, 045, 046
-- =============================================================================
begin;

set local search_path to public, extensions;

alter table public.profiles               enable row level security;
alter table public.admin_roles            enable row level security;
alter table public.notifications          enable row level security;
alter table public.payment_settings       enable row level security;
alter table public.emergency_numbers      enable row level security;
alter table public.providers              enable row level security;
alter table public.provider_skills        enable row level security;
alter table public.provider_catalog_items enable row level security;
alter table public.wallets                enable row level security;
alter table public.wallet_transactions    enable row level security;
alter table public.wallet_topup_requests  enable row level security;
alter table public.missions               enable row level security;
alter table public.mission_items          enable row level security;
alter table public.mission_events         enable row level security;
alter table public.mission_payments       enable row level security;
alter table public.mission_messages       enable row level security;
alter table public.mission_reviews        enable row level security;
alter table public.star_points_ledger     enable row level security;
alter table public.rides                  enable row level security;
alter table public.provider_reports       enable row level security;
alter table public.commission_rules       enable row level security;
alter table public.vehicles               enable row level security;
alter table public.maintenance_rules      enable row level security;

-- profiles
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or public.is_admin());
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- admin_roles
drop policy if exists admin_roles_select on public.admin_roles;
create policy admin_roles_select on public.admin_roles for select to authenticated
  using (public.is_admin());

-- notifications
drop policy if exists notifications_select on public.notifications;
create policy notifications_select on public.notifications for select to authenticated
  using (recipient_id = (select auth.uid())
         or (admins_only and public.is_admin()));
drop policy if exists notifications_mark_read on public.notifications;
create policy notifications_mark_read on public.notifications for update to authenticated
  using (recipient_id = (select auth.uid())
         or (admins_only and public.is_admin()))
  with check (recipient_id = (select auth.uid())
         or (admins_only and public.is_admin()));

-- payment_settings
drop policy if exists payment_settings_select on public.payment_settings;
create policy payment_settings_select on public.payment_settings for select to authenticated
  using (actif or public.is_admin());

-- emergency_numbers (public en lecture)
drop policy if exists emergency_numbers_select on public.emergency_numbers;
create policy emergency_numbers_select on public.emergency_numbers for select
  to anon, authenticated using (true);

-- providers
drop policy if exists providers_select on public.providers;
create policy providers_select on public.providers for select to authenticated
  using (id = (select auth.uid()) or public.is_admin());
drop policy if exists providers_update_own on public.providers;
create policy providers_update_own on public.providers for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- provider_skills / catalog_items
drop policy if exists provider_skills_select on public.provider_skills;
create policy provider_skills_select on public.provider_skills for select to authenticated
  using (provider_id = (select auth.uid()) or public.is_admin());
drop policy if exists catalog_items_select on public.provider_catalog_items;
create policy catalog_items_select on public.provider_catalog_items for select to authenticated
  using (provider_id = (select auth.uid()) or public.is_admin());

-- wallets / wallet_transactions
drop policy if exists wallets_select on public.wallets;
create policy wallets_select on public.wallets for select to authenticated
  using (provider_id = (select auth.uid()) or public.is_admin());
drop policy if exists wallet_tx_select on public.wallet_transactions;
create policy wallet_tx_select on public.wallet_transactions for select to authenticated
  using (provider_id = (select auth.uid()) or public.is_admin());

-- wallet_topup_requests
drop policy if exists topups_select on public.wallet_topup_requests;
create policy topups_select on public.wallet_topup_requests for select to authenticated
  using (provider_id = (select auth.uid()) or public.is_admin());

-- missions
drop policy if exists missions_select on public.missions;
create policy missions_select on public.missions for select to authenticated
  using (client_id = (select auth.uid())
         or provider_id = (select auth.uid())
         or public.is_admin());

-- mission_* tables
drop policy if exists mission_items_select on public.mission_items;
create policy mission_items_select on public.mission_items for select to authenticated
  using (exists (select 1 from public.missions m
                 where m.id = mission_items.mission_id
                   and (m.client_id = (select auth.uid())
                        or m.provider_id = (select auth.uid())))
         or public.is_admin());

drop policy if exists mission_events_select on public.mission_events;
create policy mission_events_select on public.mission_events for select to authenticated
  using (public.is_admin());

drop policy if exists mission_payments_select on public.mission_payments;
create policy mission_payments_select on public.mission_payments for select to authenticated
  using (exists (select 1 from public.missions m
                 where m.id = mission_payments.mission_id
                   and (m.client_id = (select auth.uid())
                        or m.provider_id = (select auth.uid())))
         or public.is_admin());

drop policy if exists mission_messages_select on public.mission_messages;
create policy mission_messages_select on public.mission_messages for select to authenticated
  using (exists (select 1 from public.missions m
                 where m.id = mission_messages.mission_id
                   and (m.client_id = (select auth.uid())
                        or m.provider_id = (select auth.uid()))));

drop policy if exists mission_reviews_select on public.mission_reviews;
create policy mission_reviews_select on public.mission_reviews for select to authenticated
  using (client_id = (select auth.uid())
         or provider_id = (select auth.uid())
         or public.is_admin());

drop policy if exists star_points_select on public.star_points_ledger;
create policy star_points_select on public.star_points_ledger for select to authenticated
  using (client_id = (select auth.uid()) or public.is_admin());

-- rides
drop policy if exists rides_select on public.rides;
create policy rides_select on public.rides for select to authenticated
  using (client_id = (select auth.uid())
         or provider_id = (select auth.uid())
         or public.is_admin());

-- provider_reports
drop policy if exists provider_reports_select on public.provider_reports;
create policy provider_reports_select on public.provider_reports for select to authenticated
  using (public.is_admin());

-- commission_rules
drop policy if exists commission_rules_select on public.commission_rules;
create policy commission_rules_select on public.commission_rules for select to authenticated
  using (public.is_admin());

-- vehicles / maintenance
drop policy if exists v_own on public.vehicles;
create policy v_own on public.vehicles for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
drop policy if exists m_own on public.maintenance_rules;
create policy m_own on public.maintenance_rules for all to authenticated
  using (exists (select 1 from public.vehicles v
                 where v.id = vehicle_id and v.owner_id = (select auth.uid())));

-- Révoquer l'écriture directe (tout passe par des RPC)
revoke insert, update, delete on
  public.profiles, public.providers, public.provider_skills,
  public.provider_catalog_items, public.missions, public.mission_items,
  public.mission_events, public.mission_payments, public.mission_messages,
  public.mission_reviews, public.star_points_ledger, public.rides,
  public.provider_reports, public.wallet_topup_requests,
  public.wallets, public.wallet_transactions,
  public.payment_settings, public.commission_rules
from authenticated, anon;

grant select on public.profiles, public.providers, public.provider_skills,
  public.provider_catalog_items, public.missions, public.mission_items,
  public.mission_payments, public.mission_messages, public.mission_reviews,
  public.star_points_ledger, public.rides, public.wallets,
  public.wallet_transactions, public.wallet_topup_requests,
  public.commission_rules
to authenticated;

grant select on public.payment_settings, public.emergency_numbers to anon, authenticated;

commit;