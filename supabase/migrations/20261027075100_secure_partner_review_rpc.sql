-- Route partner-request status changes through a trusted admin-only RPC.
create or replace function public.review_partner_request(p_request_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or coalesce(((select auth.jwt()) -> 'app_metadata' ->> 'role'), '') <> 'admin' then
    raise exception 'Administrator access required.';
  end if;
  if p_status not in ('reviewing','contacted','accepted','declined') then
    raise exception 'Choose a valid review status.';
  end if;
  update public.partner_requests
  set status = p_status, reviewed_at = now()
  where id = p_request_id;
  if not found then raise exception 'Partner request not found.'; end if;
end;
$$;
revoke all on function public.review_partner_request(uuid,text) from public, anon;
grant execute on function public.review_partner_request(uuid,text) to authenticated;
drop policy if exists "Admins can review partner requests" on public.partner_requests;
