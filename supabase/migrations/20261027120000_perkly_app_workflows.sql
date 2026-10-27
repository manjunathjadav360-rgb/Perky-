-- Perkly app policies and workflow triggers.
-- This file records the database changes applied to the connected Supabase project.

alter table public.task_completions
  add column if not exists submission_note text;

alter table public.task_completions
  drop constraint if exists task_completions_submission_note_length;

alter table public.task_completions
  add constraint task_completions_submission_note_length
  check (submission_note is null or char_length(submission_note) between 8 and 1000);

drop policy if exists "Members can request task review" on public.task_completions;
create policy "Members can request task review"
on public.task_completions
for insert to authenticated
with check (
  user_id = (select auth.uid())
  and status = 'pending'
  and exists (
    select 1 from public.earning_tasks t
    where t.id = task_id and t.active = true
  )
);

drop policy if exists "Admins can review partner requests" on public.partner_requests;
create policy "Admins can review partner requests"
on public.partner_requests
for update to authenticated
using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin')
with check (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Admins can view redemptions" on public.redemptions;
drop policy if exists "Admins can review redemptions" on public.redemptions;
create policy "Admins can review redemptions"
on public.redemptions
for update to authenticated
using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin')
with check (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

drop policy if exists "Members can view own redemptions" on public.redemptions;
create policy "Members and admins can view redemptions"
on public.redemptions
for select to authenticated
using ((select auth.uid()) = user_id or ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'admin');

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function private.credit_approved_task_completion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'approved' and old.status is distinct from new.status then
    insert into public.points_ledger
      (user_id, amount, entry_type, reference_id, description, idempotency_key, reason, source_type, source_id)
    select new.user_id, t.points, 'task_credit', new.task_id,
      'Approved activity: ' || t.title, 'task-completion:' || new.id::text,
      'Approved task completion', 'task_completion', new.id
    from public.earning_tasks t
    where t.id = new.task_id
    on conflict (idempotency_key) do nothing;
  end if;
  return new;
end;
$$;
revoke all on function private.credit_approved_task_completion() from public, anon, authenticated;

drop trigger if exists credit_points_after_task_approval on public.task_completions;
create trigger credit_points_after_task_approval
after update of status on public.task_completions
for each row
when (new.status = 'approved' and old.status is distinct from new.status)
execute function private.credit_approved_task_completion();

create or replace function public.review_redemption(p_redemption_id uuid, p_status text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_redemption public.redemptions%rowtype;
begin
  if auth.uid() is null
     or coalesce(((select auth.jwt()) -> 'app_metadata' ->> 'role'), '') <> 'admin' then
    raise exception 'Administrator access required';
  end if;
  if p_status not in ('under_review','approved','fulfilled','rejected','cancelled') then
    raise exception 'Invalid reward request status';
  end if;
  select * into v_redemption from public.redemptions where id = p_redemption_id for update;
  if not found then raise exception 'Reward request not found'; end if;
  if v_redemption.status = p_status then return v_redemption.status; end if;
  if not (
    (v_redemption.status = 'requested' and p_status in ('under_review','approved','rejected','cancelled'))
    or (v_redemption.status = 'under_review' and p_status in ('approved','rejected','cancelled'))
    or (v_redemption.status = 'approved' and p_status in ('fulfilled','cancelled'))
  ) then
    raise exception 'This reward request cannot move from % to %', v_redemption.status, p_status;
  end if;
  update public.redemptions set status = p_status, updated_at = now() where id = v_redemption.id;
  return p_status;
end;
$$;
revoke all on function public.review_redemption(uuid,text) from public, anon;
grant execute on function public.review_redemption(uuid,text) to authenticated;
drop policy if exists "Admins can review redemptions" on public.redemptions;

create or replace function private.refund_rejected_redemption()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status in ('rejected', 'cancelled')
     and old.status in ('requested', 'under_review', 'approved') then
    insert into public.points_ledger
      (user_id, amount, entry_type, reference_id, description, idempotency_key, reason, source_type, source_id)
    values
      (new.user_id, new.points_cost, 'reversal', new.id::text,
       'Refund for ' || new.status || ' reward request',
       'redemption-refund:' || new.id::text,
       'Reward request ' || new.status, 'redemption_refund', new.id)
    on conflict (idempotency_key) do nothing;
    update public.rewards set inventory = inventory + 1
      where id = new.reward_id and inventory is not null;
  end if;
  return new;
end;
$$;
revoke all on function private.refund_rejected_redemption() from public, anon, authenticated;
drop trigger if exists refund_rejected_redemption_points on public.redemptions;
create trigger refund_rejected_redemption_points
after update of status on public.redemptions
for each row
when (new.status in ('rejected', 'cancelled') and old.status in ('requested', 'under_review', 'approved'))
execute function private.refund_rejected_redemption();

-- Force reward debits and partner rate-limits through validated SECURITY DEFINER RPCs.
drop policy if exists "Members can request reward redemption" on public.redemptions;
drop policy if exists "Anyone can send partner requests" on public.partner_requests;
revoke all on function public.submit_partner_request(text,text,text,text,text,text,text,text) from public;
grant execute on function public.submit_partner_request(text,text,text,text,text,text,text,text) to anon, authenticated;

alter function public.submit_partner_request(text,text,text,text,text,text,text,text) set search_path = '';

drop policy if exists "Admins can review task completions" on public.task_completions;
