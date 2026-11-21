-- =============================================================================
-- MONTOTEM : autoriser commission_momo et commission_travel dans le wallet
-- Idempotent : peut être rejoué sans effet de bord.
-- =============================================================================
begin;

alter table public.wallet_transactions
  drop constraint if exists wallet_transactions_kind_check;

alter table public.wallet_transactions
  add constraint wallet_transactions_kind_check
  check (kind = any (array[
    'commission_cash',
    'commission_momo',
    'commission_travel',
    'topup',
    'adjustment',
    'refund'
  ]::text[]));

commit;

-- Vérification
select conname, pg_get_constraintdef(oid)
from pg_constraint
where conrelid = 'public.wallet_transactions'::regclass
  and conname = 'wallet_transactions_kind_check';