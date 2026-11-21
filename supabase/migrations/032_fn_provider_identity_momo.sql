begin;

set local search_path to public, extensions;

-- 1. Supprimer proprement les anciennes versions des fonctions pour éviter les conflits
drop function if exists public.submit_provider_identity(text,text,text,text,text,text,text,jsonb);
drop function if exists public.set_provider_momo(text, text, text);
drop function if exists public.is_own_upload_url(text, uuid);

-- 2. Recréer la fonction de vérification d'URL
create or replace function public.is_own_upload_url(p_url text, p_uid uuid)
returns boolean language sql immutable as $$
  select p_url is not null
     and p_url ~ '^https://'
     and position('/' || p_uid::text || '/' in p_url) > 0;
$$;

-- 3. Recréer la fonction de soumission d'identité
create or replace function public.submit_provider_identity(
  p_doc_type           text,
  p_doc_number         text,
  p_selfie_url         text,
  p_doc_front_url      text,
  p_doc_back_url       text,
  p_garage_photo_url   text,
  p_garage_description text default null,
  p_checks             jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  if not exists (select 1 from public.providers where id = v_uid) then
    raise exception 'PAS_PRESTATAIRE' using errcode = 'P0002';
  end if;
  if p_doc_type is null or p_doc_type not in ('cni','passeport','permis','carte_electeur') then
    raise exception 'DOCUMENT_INVALIDE' using errcode = '22023';
  end if;
  if p_doc_number is null or char_length(btrim(p_doc_number)) not between 4 and 30 then
    raise exception 'NUMERO_INVALIDE' using errcode = '22023';
  end if;
  if p_selfie_url is null or p_selfie_url not like 'https://%' then
    raise exception 'SELFIE_OBLIGATOIRE' using errcode = '22023';
  end if;
  if p_doc_front_url is null or p_doc_front_url not like 'https://%' then
    raise exception 'DOCUMENT_OBLIGATOIRE' using errcode = '22023';
  end if;
  if p_doc_type in ('cni','permis','carte_electeur')
     and (p_doc_back_url is null or p_doc_back_url not like 'https://%') then
    raise exception 'VERSO_OBLIGATOIRE' using errcode = '22023';
  end if;
  if p_garage_photo_url is null or p_garage_photo_url not like 'https://%' then
    raise exception 'PHOTO_GARAGE_OBLIGATOIRE' using errcode = '22023';
  end if;
  if not (public.is_own_upload_url(p_selfie_url, v_uid)
       or public.is_own_upload_url(p_doc_front_url, v_uid)
       or public.is_own_upload_url(p_garage_photo_url, v_uid)) then
    raise exception 'URL_INVALIDE' using errcode = '22023';
  end if;

  update public.providers
     set id_document_type      = p_doc_type,
         id_document_number    = btrim(p_doc_number),
         photo_selfie_url      = p_selfie_url,
         photo_cni_url         = p_doc_front_url,
         photo_cni_back_url    = p_doc_back_url,
         photo_garage_url      = p_garage_photo_url,
         garage_description    = left(nullif(btrim(p_garage_description), ''), 500),
         id_checks             = coalesce(p_checks, '{}'::jsonb),
         identity_submitted_at = now(),
         statut_validation     = case when statut_validation = 'rejected'
                                      then 'pending' else statut_validation end,
         rejection_reason      = case when statut_validation = 'rejected'
                                      then null else rejection_reason end,
         updated_at            = now()
   where id = v_uid;

  perform public.safe_notify_admins(
    'identity_submitted', 'Dossier d''identité soumis',
    'Un prestataire a soumis ses documents pour vérification.',
    jsonb_build_object('provider_id', v_uid));
end;
$$;
revoke all on function public.submit_provider_identity(
  text,text,text,text,text,text,text,jsonb) from public, anon;
grant execute on function public.submit_provider_identity(
  text,text,text,text,text,text,text,jsonb) to authenticated;

-- 4. Recréer la fonction de configuration MoMo
create or replace function public.set_provider_momo(
  p_operateur text,
  p_numero    text,
  p_titulaire text default null
) returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_num text := regexp_replace(coalesce(p_numero, ''), '\s+', '', 'g');
begin
  if v_uid is null then raise exception 'NON_CONNECTE' using errcode = '28000'; end if;
  if p_operateur is null or p_operateur not in ('mtn','moov','celtiis') then
    raise exception 'OPERATEUR_INVALIDE' using errcode = '22023';
  end if;
  if v_num !~ '^\+?[0-9]{8,15}$' then
    raise exception 'TELEPHONE_INVALIDE' using errcode = '22023';
  end if;
  if not exists (select 1 from public.providers where id = v_uid) then
    raise exception 'PAS_PRESTATAIRE' using errcode = 'P0002';
  end if;

  update public.providers
     set momo_operateur = p_operateur,
         momo_numero    = v_num,
         momo_titulaire = left(nullif(btrim(p_titulaire), ''), 80),
         updated_at     = now()
   where id = v_uid;
end;
$$;
revoke all on function public.set_provider_momo(text, text, text) from public, anon;
grant execute on function public.set_provider_momo(text, text, text) to authenticated;

commit;