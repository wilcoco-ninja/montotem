-- =============================================================================
-- 051 — Storage : buckets avatars (public) et documents (privé)
-- Dart : auth_service.dart (uploaderDocument)
-- Dépend de : 010, 050
-- =============================================================================
begin;

-- Le chemin doit être <uid>/..., providers/<uid>/... ou clients/<uid>/...
create or replace function public.storage_owner_ok(p_name text)
returns boolean language sql stable as $$
  select auth.uid() is not null
     and coalesce(cardinality(storage.foldername(p_name)), 0) >= 1
     and ((storage.foldername(p_name))[1] = auth.uid()::text
          or ((storage.foldername(p_name))[1] in ('providers','clients')
              and (storage.foldername(p_name))[2] = auth.uid()::text));
$$;

-- Avatars (public bucket)
drop policy if exists storage_avatars_select on storage.objects;
drop policy if exists storage_avatars_insert on storage.objects;
drop policy if exists storage_avatars_update on storage.objects;
drop policy if exists storage_avatars_delete on storage.objects;

create policy storage_avatars_select on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (public.storage_owner_ok(name) or public.is_admin()));
create policy storage_avatars_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and public.storage_owner_ok(name));
create policy storage_avatars_update on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and public.storage_owner_ok(name))
  with check (bucket_id = 'avatars' and public.storage_owner_ok(name));
create policy storage_avatars_delete on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and public.storage_owner_ok(name));

-- Documents (privé)
drop policy if exists storage_documents_select on storage.objects;
drop policy if exists storage_documents_insert on storage.objects;
drop policy if exists storage_documents_update on storage.objects;
drop policy if exists storage_documents_delete on storage.objects;

create policy storage_documents_select on storage.objects for select to authenticated
  using (bucket_id = 'documents' and (public.storage_owner_ok(name) or public.is_admin()));
create policy storage_documents_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'documents' and public.storage_owner_ok(name));
create policy storage_documents_update on storage.objects for update to authenticated
  using (bucket_id = 'documents' and public.storage_owner_ok(name))
  with check (bucket_id = 'documents' and public.storage_owner_ok(name));
create policy storage_documents_delete on storage.objects for delete to authenticated
  using (bucket_id = 'documents' and public.storage_owner_ok(name));

commit;