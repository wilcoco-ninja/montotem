-- =============================================================================
-- 033 — Compétences libres
-- Dart : provider_skills_service.dart
-- Dépend de : 014
-- =============================================================================
begin;

set local search_path to public, extensions;

create or replace function public.add_provider_skill(p_label text)
returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid   uuid := auth.uid();
  v_label text := regexp_replace(btrim(coalesce(p_label, '')), '\s+', ' ', 'g');
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  if not exists (select 1 from public.providers where id = v_uid) then
    raise exception 'PAS_PRESTATAIRE' using errcode = 'P0002';
  end if;
  if char_length(v_label) not between 2 and 60 then
    raise exception 'COMPETENCE_INVALIDE' using errcode = '22023';
  end if;
  if (select count(*) from public.provider_skills where provider_id = v_uid) >= 30 then
    raise exception 'TROP_DE_COMPETENCES' using errcode = 'P0001';
  end if;
  insert into public.provider_skills (provider_id, label)
  values (v_uid, v_label)
  on conflict do nothing;
end;
$$;
revoke all on function public.add_provider_skill(text) from public, anon;
grant execute on function public.add_provider_skill(text) to authenticated;

create or replace function public.remove_provider_skill(p_id uuid)
returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  delete from public.provider_skills where id = p_id and provider_id = v_uid;
end;
$$;
revoke all on function public.remove_provider_skill(uuid) from public, anon;
grant execute on function public.remove_provider_skill(uuid) to authenticated;

commit;