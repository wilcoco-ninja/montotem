-- =============================================================================
-- 015 — Wallets prestataire + recharges
-- Dart : wallet_service.dart, wallet_model.dart, provider_wallet_screen.dart,
--        admin_topup_service.dart
-- Dépend de : 013
-- =============================================================================
begin;

set local search_path to public, extensions;

-- Dart : Wallet.fromJson (provider_id, balance_fcfa, blocked, ...)
create table if not exists public.wallets (
  provider_id  uuid primary key references public.providers(id) on delete cascade,
  balance_fcfa integer not null default 0,
  blocked      boolean not null default false,
  blocked_at   timestamptz,
  block_reason text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Dart : WalletTransaction.fromJson (kind, amount_fcfa, balance_after, ...)
create table if not exists public.wallet_transactions (
  id            bigint generated always as identity primary key,
  provider_id   uuid not null references public.wallets(provider_id) on delete cascade,
  ride_id       uuid,
  kind          text not null check (kind in
                ('commission_cash','commission_momo','commission_travel',
                 'topup','adjustment','refund')),
  amount_fcfa   integer not null check (amount_fcfa <> 0),
  balance_after integer not null,
  reference     text,
  note          text,
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now()
);

create index if not exists idx_wallet_tx_provider
  on public.wallet_transactions (provider_id, created_at desc);
create unique index if not exists uq_wallet_tx_reference
  on public.wallet_transactions (reference) where reference is not null;
create unique index if not exists uq_wallet_tx_ride_commission
  on public.wallet_transactions (ride_id) where kind in ('commission_cash','commission_momo');

-- Wallet créé automatiquement à l'inscription prestataire
create or replace function public.providers_create_wallet()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.wallets (provider_id) values (new.id) on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists trg_providers_create_wallet on public.providers;
create trigger trg_providers_create_wallet
  after insert on public.providers
  for each row execute function public.providers_create_wallet();

-- Blocage auto si solde < seuil négatif
create or replace function public.wallets_auto_block()
returns trigger language plpgsql security definer
set search_path = public, extensions
as $$
declare v_threshold integer;
begin
  select value_int into v_threshold from public.app_config
   where key = 'wallet_block_threshold_fcfa';
  v_threshold := coalesce(v_threshold, 2000);
  new.updated_at := now();
  if new.balance_fcfa < -v_threshold then
    if not new.blocked then
      new.blocked := true;
      new.blocked_at := now();
      new.block_reason := 'WALLET_SOUS_SEUIL';
    end if;
  elsif new.blocked and new.block_reason = 'WALLET_SOUS_SEUIL' then
    new.blocked := false;
    new.blocked_at := null;
    new.block_reason := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_wallets_auto_block on public.wallets;
create trigger trg_wallets_auto_block
  before insert or update of balance_fcfa on public.wallets
  for each row execute function public.wallets_auto_block();

-- Dart : TopupRequest.fromJson
create table if not exists public.wallet_topup_requests (
  id               uuid primary key default gen_random_uuid(),
  provider_id      uuid not null references public.providers(id) on delete cascade,
  amount_fcfa      integer not null check (amount_fcfa between 500 and 1000000),
  operateur        text not null check (operateur in ('mtn','moov','celtiis')),
  payer_phone      text not null,
  transaction_ref  text not null,
  statut           text not null default 'awaiting_validation'
                   check (statut in ('awaiting_validation','approved','rejected')),
  rejection_reason text,
  reviewed_by      uuid references public.profiles(id) on delete set null,
  reviewed_at      timestamptz,
  created_at       timestamptz not null default now()
);
create index if not exists idx_topups_provider
  on public.wallet_topup_requests (provider_id, created_at desc);
create index if not exists idx_topups_statut
  on public.wallet_topup_requests (statut, created_at desc);
create unique index if not exists uq_topups_reference_active
  on public.wallet_topup_requests (lower(transaction_ref)) where statut <> 'rejected';
create unique index if not exists uq_topups_one_pending
  on public.wallet_topup_requests (provider_id) where statut = 'awaiting_validation';

commit;