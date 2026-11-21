-- =============================================================================
-- MONTOTEM : idempotence des commissions MoMo (par course)
-- Une course ne peut être commissionnée qu'une fois en 'commission_momo'.
-- La commission de trajet est protégée par uq_wallet_tx_reference
-- (reference = 'trajet:<id du paiement>').
-- =============================================================================
begin;

create unique index if not exists uq_wallet_tx_ride_commission_momo
  on public.wallet_transactions (ride_id)
  where kind = 'commission_momo';

commit;

-- Vérification
select indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename = 'wallet_transactions'
  and indexname like 'uq_wallet_tx_%'
order by indexname;