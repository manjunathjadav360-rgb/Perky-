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

drop policy if exists "Members can request reward redemption" on public.redemptions;
create policy "Members can request reward redemption"
on public.redemptions
for insert to authenticated
with check (
  user_id = (select auth.uid())
  and status = 'requested'
  and exists (
    select 1 from public.rewards r
    where r.id = reward_id
      and r.active = true
      and r.points_cost = redemptions.points_cost
  )
  and (
    coalesce((select sum(pl.amount) from public.points_ledger pl where pl.user_id = (select auth.uid())), 0)
    - coalesce((select sum(rd.points_cost) from public.redemptions rd where rd.user_id = (select auth.uid()) and rd.status in ('requested','under_review','approved')), 0)
  ) >= points_cost
);

drop policy if exists "Anyone can send partner requests" on public.partner_requests;
create policy "Anyone can send partner requests"
on public.partner_requests
for insert to anon, authenticated
with check (
  status = 'new'
  and char_length(trim(company_name)) between 2 and 120
  and char_length(trim(contact_name)) between 2 and 100
  and char_length(trim(contact_email)) between 5 and 254
  and position('@' in contact_email) > 1
  and char_length(trim(message)) between 10 and 3000
);

drop policy if exists "Admins can review task completions" on public.task_completions;
create policy "Admins can review task completions"
on public.task_completions
for update to authenticated
using ((select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')) = 'admin')
with check ((select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')) = 'admin');

drop policy if exists "Admins can review partner requests" on public.partner_requests;
create policy "Admins can review partner requests"
on public.partner_requests
for update to authenticated
using ((select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')) = 'admin')
with check ((select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')) = 'admin');

drop policy if exists "Admins can view redemptions" on public.redemptions;
create policy "Admins can view redemptions"
on public.redemptions
for select to authenticated
using ((select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')) = 'admin');

drop policy if exists "Admins can review redemptions" on public.redemptions;
create policy "Admins can review redemptions"
on public.redemptions
for update to authenticated
using ((select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')) = 'admin')
with check ((select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '')) = 'admin');

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

create or replace function private.refund_rejected_redemption()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status in ('rejected', 'cancelled') and old.status not in ('rejected', 'cancelled') then
    insert into public.points_ledger
      (user_id, amount, entry_type, reference_id, description, idempotency_key, reason, source_type, source_id)
    values
      (new.user_id, new.points_cost, 'reversal', new.id::text,
       'Refund for ' || new.status || ' reward request',
       'redemption-refund:' || new.id::text,
       'Reward request ' || new.status, 'redemption_refund', new.id)
    on conflict (idempotency_key) do nothing;
  end if;
  return new;
end;
$$;
revoke all on function private.refund_rejected_redemption() from public, anon, authenticated;

drop trigger if exists refund_rejected_redemption_points on public.redemptions;
create trigger refund_rejected_redemption_points
after update of status on public.redemptions
for each row
when (new.status in ('rejected', 'cancelled') and old.status is distinct from new.status)
execute function private.refund_rejected_redemption();
