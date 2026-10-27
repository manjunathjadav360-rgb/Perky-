-- A client cannot redeem a sample/preview reward by calling the RPC directly.
create or replace function public.redeem_reward(p_reward_id text, p_idempotency_key text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_reward public.rewards%rowtype;
  v_redemption_id uuid;
  v_existing public.redemptions%rowtype;
  v_balance bigint;
begin
  if v_user_id is null then raise exception 'Sign in is required'; end if;
  if p_reward_id is null or length(trim(p_reward_id)) = 0 then raise exception 'Reward is required'; end if;
  if p_idempotency_key is null or length(p_idempotency_key) < 8 or length(p_idempotency_key) > 160 then
    raise exception 'Invalid request key';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user_id::text, 0));
  select * into v_existing from public.redemptions
    where user_id = v_user_id and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.reward_id <> p_reward_id then raise exception 'Request key already used for another reward'; end if;
    return v_existing.id;
  end if;
  select * into v_reward from public.rewards where id = p_reward_id and active = true for update;
  if not found then raise exception 'Reward is not available'; end if;
  if v_reward.reward_type = 'sample' then raise exception 'This reward is a preview and cannot be redeemed'; end if;
  if v_reward.inventory is not null and v_reward.inventory <= 0 then raise exception 'Reward is out of stock'; end if;
  select coalesce(sum(l.amount), 0) into v_balance from public.points_ledger l where l.user_id = v_user_id;
  if v_balance < v_reward.points_cost then raise exception 'Not enough points'; end if;
  insert into public.redemptions(user_id, reward_id, points_cost, status, idempotency_key)
    values (v_user_id, v_reward.id, v_reward.points_cost, 'requested', p_idempotency_key)
    returning id into v_redemption_id;
  insert into public.points_ledger(user_id, amount, entry_type, reference_id, description, reason, source_type, source_id, idempotency_key)
    values (v_user_id, -v_reward.points_cost, 'redemption_debit', v_redemption_id::text,
      'Reward request: ' || v_reward.title, 'Reward redemption request', 'redemption', v_redemption_id,
      'redemption:' || v_user_id::text || ':' || p_idempotency_key);
  if v_reward.inventory is not null then
    update public.rewards set inventory = inventory - 1 where id = v_reward.id and inventory > 0;
    if not found then raise exception 'Reward is out of stock'; end if;
  end if;
  return v_redemption_id;
end;
$$;
revoke all on function public.redeem_reward(text,text) from public, anon;
grant execute on function public.redeem_reward(text,text) to authenticated;
