-- Allow a member to retry an activity after rejection, while preventing duplicate
-- pending/approved submissions. Daily check-ins remain limited to one active
-- submission per UTC day.
drop index if exists public.task_completions_once_unique_idx;
drop index if exists public.task_completions_daily_unique_idx;
create unique index task_completions_once_unique_idx
  on public.task_completions(user_id, task_id)
  where recurrence = 'once' and status in ('pending','approved');
create unique index task_completions_daily_unique_idx
  on public.task_completions(user_id, task_id, completion_day)
  where recurrence = 'daily' and status in ('pending','approved');

create or replace function public.submit_task_completion(
  p_task_id text,
  p_submission_note text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_completion_id uuid;
  v_existing_task_id text;
  v_recurrence text;
  v_day date := (pg_catalog.now() at time zone 'UTC')::date;
begin
  if v_user_id is null then raise exception 'Sign in is required'; end if;
  if p_task_id is null or length(trim(p_task_id)) = 0 then raise exception 'Task is required'; end if;
  if p_submission_note is null or length(trim(p_submission_note)) not between 8 and 1000 then
    raise exception 'Add a short activity note (8–1000 characters).';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 160 then
    raise exception 'Invalid request key';
  end if;
  select t.recurrence into v_recurrence
  from public.earning_tasks t where t.id = p_task_id and t.active = true;
  if not found then raise exception 'Task is not available'; end if;
  insert into public.task_completions
    (user_id, task_id, submission_note, idempotency_key, status, recurrence, completion_day)
  values (v_user_id, p_task_id, trim(p_submission_note), p_idempotency_key, 'pending', v_recurrence, v_day)
  returning id into v_completion_id;
  return v_completion_id;
exception
  when unique_violation then
    select tc.id, tc.task_id into v_completion_id, v_existing_task_id
    from public.task_completions tc
    where tc.user_id = v_user_id and tc.idempotency_key = p_idempotency_key
    limit 1;
    if v_completion_id is not null then
      if v_existing_task_id <> p_task_id then raise exception 'Request key already used for another activity'; end if;
      return v_completion_id;
    end if;
    if v_recurrence = 'daily' and exists (
      select 1 from public.task_completions tc
      where tc.user_id = v_user_id and tc.task_id = p_task_id
        and tc.recurrence = 'daily' and tc.completion_day = v_day
        and tc.status in ('pending','approved')
    ) then raise exception 'You have already submitted this daily activity today.'; end if;
    if v_recurrence = 'once' and exists (
      select 1 from public.task_completions tc
      where tc.user_id = v_user_id and tc.task_id = p_task_id
        and tc.recurrence = 'once' and tc.status in ('pending','approved')
    ) then raise exception 'You have already submitted this activity.'; end if;
    raise;
end;
$$;
revoke all on function public.submit_task_completion(text,text,text) from public, anon;
grant execute on function public.submit_task_completion(text,text,text) to authenticated;
