-- =============================================================================
-- MONTOTEM : Script 04 - Test de déclenchement d'une notification utilisateur
-- Fichier  : 04_test_notifications.sql
-- =============================================================================

begin;

-- 1. Création sécurisée de la table des notifications si elle n'existe pas encore
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

-- 2. Création de la fonction notify_user si elle manque
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

commit;

-- 3. Envoi de la notification de test
select public.notify_user(
  '4531149b-e53d-4dc8-a6f2-a02411419547', 
  'provider_approved', 
  'Test MONTOTEM',
  'Si vous lisez ceci, les notifications push fonctionnent.', 
  '{}'::jsonb
);