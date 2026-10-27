-- Require authenticated activity submissions to pass server-side validation and include a note.
drop policy if exists "Members can request task review" on public.task_completions;
drop function if exists public.submit_task_completion(text,text);

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
begin
  if v_user_id is null then raise exception 'Sign in is required'; end if;
  if p_task_id is null or length(trim(p_task_id)) = 0 then raise exception 'Task is required'; end if;
  if p_submission_note is null or length(trim(p_submission_note)) not between 8 and 1000 then
    raise exception 'Add a short activity note (8–1000 characters).';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 160 then
    raise exception 'Invalid request key';
  end if;
  if not exists (select 1 from public.earning_tasks t where t.id = p_task_id and t.active = true) then
    raise exception 'Task is not available';
  end if;
  insert into public.task_completions(user_id, task_id, submission_note, idempotency_key, status)
  values (v_user_id, p_task_id, trim(p_submission_note), p_idempotency_key, 'pending')
  returning id into v_completion_id;
  return v_completion_id;
exception
  when unique_violation then
    select tc.id into v_completion_id
    from public.task_completions tc
    where tc.user_id = v_user_id and tc.idempotency_key = p_idempotency_key
    limit 1;
    if v_completion_id is not null then return v_completion_id; end if;
    if exists (select 1 from public.task_completions tc where tc.user_id = v_user_id and tc.task_id = p_task_id) then
      raise exception 'You have already submitted this activity.';
    end if;
    raise;
end;
$$;
revoke all on function public.submit_task_completion(text,text,text) from public, anon;
grant execute on function public.submit_task_completion(text,text,text) to authenticated;
